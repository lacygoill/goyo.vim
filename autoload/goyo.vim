vim9script noclear

# Interface {{{1
def goyo#execute(bang: bool, dim: string) #{{{2
# "dim" = dimensions

    # I'm frequently pressing `zz` when entering goyo mode.
    # Might as well make `:Goyo` do it automatically for me.
    normal! zz
    if bang
        if exists('#goyo')
            GoyoOff()
        endif
    else
        if exists('#goyo') == 0
            GoyoOn(dim)
        elseif !empty(dim)
            if winnr('$') < 5
                GoyoOff()
                return goyo#execute(bang, dim)
            endif
            var parsed_dim: dict<number> = ParseArg(dim)
            if !empty(parsed_dim)
                t:goyo_dim = parsed_dim
                t:goyo_dim_expr = dim
                ResizePads()
            endif
        else
            GoyoOff()
        endif
    endif
enddef

def goyo#start(without_hl = true) #{{{2
    without_highlighting = without_hl
    if exists('#goyo')
        goyo#execute(true, '')
    else
        goyo#execute(false, '110')
    endif
enddef

def goyo#enter() #{{{2
    # Is inspected by other plugins to adapt their behavior.
    # E.g.: vim-toggle-settings (mappings toggling `'cursorline'`).
    g:in_goyo_mode = true
    silent system('tmux set status off')
    # FIXME: If we have 2 tmux panes in the same window, Vim is one of them, and
    # it's not zoomed, when we start goyo mode, we see much less text as usual.
    # If we have 2 vertical panes, the lines are shorter.
    # If we have 2 horizontal panes, there are fewer lines.
    silent system('[[ $(tmux display -p "#{window_zoomed_flag}") -eq 0 ]] && tmux resizep -Z')
    &showcmd = false

    [winid_save, bufnr_save] = [win_getid(), bufnr('%')]
    [concealcursor_save, conceallevel_save] = [&l:concealcursor, &l:conceallevel]
    &l:concealcursor = 'nc'
    &l:conceallevel = 3

    var pos: list<number> = getcurpos()
    # The new window  created by `:tab split` inherits  the window-local options
    # of the original window.  But `:tab split` doesn't fire `BufWinEnter` so we
    # lose our position in the changelist.
    doautocmd <nomodeline> BufWinEnter
    setpos('.', pos)

    augroup MyGoyo
        autocmd! * <buffer>
        # make sure cursor is not on leading whitespace
        autocmd CursorHold <buffer> if getline('.')->match('^\s*\%.c\s') >= 0
            |     execute 'normal! _'
            | endif
        # clear possible error message from command-line (e.g. `E486`)
        autocmd CursorHold <buffer> echo
    augroup END
    # The autocmd doesn't work initially, probably because `CursorHold` has already been fired.{{{
    #
    # We could run `doautocmd CursorHold` now, but I prefer `normal! _`:
    # fewer side effects, and position the cursor in a known location right from
    # the start (helpful with an underline cusor which is harder to spot).
    #}}}
    normal! _

    auto_open_fold_was_enabled = true
    if !exists('b:auto_open_fold_mappings')
        auto_open_fold_was_enabled = false
        toggleSettings#autoOpenFold(true)
    endif

    # We want to be able to read code blocks in our notes (and probably other syntax groups).
    if &filetype == 'markdown'
        return
    endif

    Limelight

    if without_highlighting
        var syntax_groups: list<string> = execute('syntax list')
            ->split('\n')
            ->filter((_, v: string): bool => v =~ '^\S\+\s\+xxx\s')
            ->map((_, v: string) => v->matchstr('^\S\+'))
            # we still want to keep the comments
            ->filter((_, v: string): bool => v !~ '\ccomment')

        for group: string in syntax_groups
            execute 'syntax clear ' .. group
        endfor
    endif
enddef

var concealcursor_save: string
var conceallevel_save: number
var winid_save: number
var bufnr_save: number
var without_highlighting: bool
var auto_open_fold_was_enabled: bool

def goyo#leave() #{{{2
    unlet! g:in_goyo_mode

    silent system('tmux set status on')
    silent system('[[ $(tmux display -p "#{window_zoomed_flag}") -eq 0 ]] && tmux resizep -Z')

    &showcmd = true
    if winbufnr(winid_save) == bufnr_save
        var tabnr: number
        var winnr: number
        [tabnr, winnr] = win_id2tabwin(winid_save)
        settabwinvar(tabnr, winnr, '&concealcursor', concealcursor_save)
        settabwinvar(tabnr, winnr, '&conceallevel', conceallevel_save)
    endif
    concealcursor_save = ''
    conceallevel_save = 0
    winid_save = 0
    bufnr_save = 0

    # TODO: Refactor all `:wincmd` into `win_execute()`.{{{
    #
    # In Vim,  if we've entered  goyo mode in the  bottom split of  2 horizontal
    # splits, when we  leave goyo mode, the top window  is not squashed anymore;
    # it's 1 line high; it's probably due to the usage of `:wincmd` somewhere in
    # this plugin.
    #
    # For the moment, we fix the  issue by firing `WinEnter`, so that vim-window
    # re-maximizes the current window, which will squash the top window.
    #
    # Once you've refactored all `:wincmd` into `win_execute()`, remove the next
    # `:doautocmd`.
    #}}}
    doautocmd <nomodeline> WinEnter

    autocmd! MyGoyo * <buffer>
    # bang to suppress `:help W19`
    silent! augroup! MyGoyo

    Limelight!
    if !auto_open_fold_was_enabled && exists('b:auto_open_fold_mappings')
        toggleSettings#autoOpenFold(false)
    endif
enddef

def goyo#island() #{{{2
    var should_collapse: bool = line("'<") > 2
        && (line("'<") - 1)->getline() =~ '^\s*$'
        && (line("'<") - 2)->getline() =~ '^\s*$'
        && line("'>") < line('$') - 1
        && (line("'>") + 1)->getline() =~ '^\s*$'
        && (line("'>") + 2)->getline() =~ '^\s*$'
    if should_collapse
        # remove superflous empty lines below
        keepjumps keeppatterns :'>+1 substitute/^\%(\_s*\n\)\+/\r/e
        # same thing above
        # The order of removal is important.{{{
        #
        # We need to remove the empty lines below, before the ones above.
        # That is because removing the lines  above will change the addresses of
        # the line below.
        #}}}
        keepjumps keeppatterns :'<?^\s*\S?+1 substitute/^\%(\_s*\n\)\+/\r/e
        # the mark set on the start of  the selection has been moved to the next line;
        # restore it
        :'<-1 mark <
    else
        # add empty lines to clear the view
        var cnt: number = winheight(0) / 2
        repeat([''], cnt)->append(line("'<") - 1)
        repeat([''], cnt)->append(line("'>"))
    endif
    normal! '<zz
enddef
#}}}1
# Core {{{1
def Const( #{{{2
    val: number,
    min: number,
    max: number
): number
    return [max([val, min]), max]->min()
enddef

def GetColor(group: string, attr: string): string #{{{2
    return hlID(group)->synIDtrans()->synIDattr(attr)
enddef

def SetColor( #{{{2
    group: string,
    attr: string,
    color: string
)
    var gui: bool = has('gui_running') || has('termguicolors') && &termguicolors
    execute printf('highlight %s %s%s=%s', group, gui ? 'gui' : 'cterm', attr, color)
enddef

def Blank(repel: string) #{{{2
    if bufwinnr(t:goyo_pads.r) <= bufwinnr(t:goyo_pads.l) + 1
    || bufwinnr(t:goyo_pads.b) <= bufwinnr(t:goyo_pads.t) + 3
        GoyoOff()
    endif
    execute 'wincmd ' .. repel
enddef

def InitPad(command: string): number #{{{2
    execute command

    &l:bufhidden = 'wipe'
    &l:buflisted = false
    &l:buftype = 'nofile'
    &l:colorcolumn = ''
    &l:cursorcolumn = false
    &l:cursorline = false
    &l:modifiable = false
    &l:number = false
    &l:relativenumber = false
    &l:statusline = ' '
    &l:swapfile = false
    &l:winfixheight = true
    &l:winfixwidth = true

    var bufnr: number = winbufnr(0)
    wincmd p
    return bufnr
enddef

def SetupPad( #{{{2
    bufnr: number,
    vert: bool,
    size: number,
    repel: string
)
    var win: number = bufwinnr(bufnr)
    win_getid(win)->win_gotoid()
    # TODO: I think  this doesn't work  as expected  for the height,  because of
    # `vim-window` which maximizes windows' height.
    execute (vert ? 'vertical ' : '') .. 'resize ' .. max([0, size])
    augroup goyop
        BlankRef = function(Blank, [repel])
        autocmd WinEnter,CursorMoved <buffer> ++nested BlankRef()
        autocmd WinLeave <buffer> HideStatusline()
    augroup END

    # to hide scrollbars of pad windows in the GUI
    var diff: number = winheight(0) - line('$') - (has('gui_running') ? 2 : 0)
    if diff > 0
        &l:modifiable = true
        ['']->repeat(diff)->append(0)
        normal! gg
        &l:modifiable = false
    endif
    wincmd p
enddef
var BlankRef: func

def ResizePads() #{{{2
    augroup goyop | autocmd!
    augroup END

    t:goyo_dim.width = Const(t:goyo_dim.width, 2, &columns)
    t:goyo_dim.height = Const(t:goyo_dim.height, 2, &lines)

    var vmargin: number = max([0, (&lines - t:goyo_dim.height) / 2 - 1])
    var yoff: number = Const(t:goyo_dim.yoff, - vmargin, vmargin)
    var top: number = vmargin + yoff
    var bot: number = vmargin - yoff - 1
    SetupPad(t:goyo_pads.t, false, top, 'j')
    SetupPad(t:goyo_pads.b, false, bot, 'k')

    var nwidth: number = max([line('$')->len() + 1, &numberwidth])
    var width: number = t:goyo_dim.width + (&number ? nwidth : 0)
    var hmargin: number = max([0, (&columns - width) / 2 - 1])
    var xoff: number = Const(t:goyo_dim.xoff, - hmargin, hmargin)
    SetupPad(t:goyo_pads.l, true, hmargin + xoff, 'l')
    SetupPad(t:goyo_pads.r, true, hmargin - xoff, 'h')
enddef

def Tranquilize() #{{{2
    var bg: string = GetColor('Normal', 'bg#')
    for grp: string in ['NonText', 'FoldColumn', 'ColorColumn', 'VertSplit',
        'StatusLine', 'StatusLineNC', 'SignColumn']
        if empty(bg)
            SetColor(grp, 'fg', 'black')
            SetColor(grp, 'bg', 'NONE')
        else
            SetColor(grp, 'fg', bg)
            SetColor(grp, 'bg', bg)
        endif
        SetColor(grp, '', 'NONE')
    endfor
enddef

def HideStatusline() #{{{2
    &l:statusline = ' '
enddef

def HideLinenr() #{{{2
    &l:number = false
    &l:relativenumber = false
    &l:colorcolumn = ''
enddef

def MapsNop(): list<string> #{{{2
    var mapped: list<string> = ['R', 'H', 'J', 'K', 'L', '|', '_']
        ->filter((_, v: string): bool => maparg("\<C-W>" .. v, 'n')->empty())
    for c: string in mapped
        execute 'nnoremap <C-W>' .. escape(c, '|') .. ' <Nop>'
    endfor
    return mapped
enddef

def MapsResize(): list<string> #{{{2
    var commands: dict<string> = {
        '=': '<Cmd>let t:goyo_dim = <SID>ParseArg(t:goyo_dim_expr) <Bar> call <sid>ResizePads()<CR>',
        '>': '<Cmd>let t:goyo_dim.width = winwidth(0) + 2 * v:count1 <Bar> call <SID>ResizePads()<CR>',
        '<': '<Cmd>let t:goyo_dim.width = winwidth(0) - 2 * v:count1 <Bar> call <SID>ResizePads()<CR>',
        '+': '<Cmd>let t:goyo_dim.height += 2 * v:count1 <Bar> call <SID>ResizePads()<CR>',
        '-': '<Cmd>let t:goyo_dim.height -= 2 * v:count1 <Bar> call <SID>ResizePads()<CR>'
    }
    var mapped: list<string> = commands
        ->keys()
        ->filter((_, v: string): bool => maparg("\<C-W>" .. v, 'n')->empty())
    for c: string in mapped
        execute 'nnoremap <C-W>' .. c .. ' ' .. commands[c]
    endfor
    return mapped
enddef

nnoremap <Plug>(goyo-resize) <Cmd>call <SID>ResizePads()<CR>

def GoyoOn(arg_dim: string) #{{{2
    var dim: dict<number> = ParseArg(arg_dim)
    if empty(dim)
        return
    endif

    orig_tab = tabpagenr()
    var settings: dict<any> = {
        laststatus: &laststatus,
        showtabline: &showtabline,
        fillchars: &fillchars,
        winminwidth: &winminwidth,
        winwidth: &winwidth,
        winminheight: &winminheight,
        winheight: &winheight,
        ruler: &ruler,
        sidescroll: &sidescroll,
        sidescrolloff: &sidescrolloff,
    }

    tab split

    t:goyo_master = winbufnr(0)
    t:goyo_dim = dim
    t:goyo_dim_expr = arg_dim
    t:goyo_pads = {}
    t:goyo_revert = settings
    t:goyo_maps = MapsNop()->extend(MapsResize())
    if has('gui_running')
        t:goyo_revert.guioptions = &guioptions
    endif

    HideLinenr()
    # Global options
    &winheight = [&winminheight, 1]->max()
    &winminheight = 1
    &winheight = 1
    &winminwidth = 1
    &winwidth = 1
    &laststatus = 0
    &showtabline = 0
    &ruler = false
    &fillchars ..= ',vert: ,stl: ,stlnc: '
    &sidescroll = 1
    &sidescrolloff = 0

    # Hide left-hand scrollbars
    if has('gui_running')
        set guioptions-=l
        set guioptions-=L
    endif

    t:goyo_pads.l = InitPad('vertical topleft new')
    t:goyo_pads.r = InitPad('vertical botright new')
    t:goyo_pads.t = InitPad('topleft new')
    t:goyo_pads.b = InitPad('botright new')

    ResizePads()
    Tranquilize()

    augroup goyo | autocmd!
        autocmd TabLeave * ++nested GoyoOff()
        autocmd VimResized * ResizePads()
        autocmd ColorScheme * Tranquilize()
        autocmd BufWinEnter * HideLinenr() | HideStatusline()
        autocmd WinEnter,WinLeave * HideStatusline()
    augroup END

    HideStatusline()
    if exists('#User#GoyoEnter')
        doautocmd <nomodeline> User GoyoEnter
    endif
enddef
var orig_tab: number

def GoyoOff() #{{{2
    if !exists('#goyo')
        return
    endif

    # Oops, not this tab
    if !exists('t:goyo_revert')
        return
    endif

    # Clear auto commands
    autocmd! goyo
    augroup! goyo
    autocmd! goyop
    augroup! goyop

    for c: string in t:goyo_maps
        execute 'nunmap <C-W>' .. escape(c, '|')
    endfor

    var goyo_revert: dict<any> = t:goyo_revert
    var goyo_orig_buffer: number = t:goyo_master
    var view: dict<number> = winsaveview()

    if tabpagenr() == 1
        tabnew
        normal! gt
        bdelete
    endif
    tabclose
    execute 'normal! ' .. orig_tab .. 'gt'
    if winbufnr(0) == goyo_orig_buffer
        view->winrestview()
        normal! zv
    endif

    var winminwidth: number = remove(goyo_revert, 'winminwidth')
    var whichwrap: number = remove(goyo_revert, 'winwidth')
    &winwidth = whichwrap
    &winminwidth = winminwidth
    var winminheight: number = remove(goyo_revert, 'winminheight')
    var winheight: number = remove(goyo_revert, 'winheight')
    &winheight = max([winminheight, 1])
    &winminheight = winminheight
    &winheight = winheight

    for [k: string, v: any] in goyo_revert->items()
        execute printf('&%s = %s', k, string(v))
    endfor

    # Necessary  because  we've  temporarily  reset  some  highlight  groups  in
    # `Tranquilize()` (like  `StatusLine`), so  that they become  invisible.  We
    # want them back now, with their original colors.
    execute 'colorscheme ' .. get(g:, 'colors_name', 'default')
    doautocmd Syntax

    if exists('#User#GoyoLeave')
        doautocmd <nomodeline> User GoyoLeave
    endif
enddef

def Relsz(expr: string, limit: number): number #{{{2
    if expr !~ '%$'
        return str2nr(expr)
    endif
    return limit * str2nr(expr[: -2]) / 100
enddef

def ParseArg(arg: string): dict<number> #{{{2
    var height: number = '85%'->Relsz(&lines)
    var yoff: number = 0

    var dim: dict<number> = {
        width: '80'->Relsz(&columns),
        height: height,
        xoff: 0,
        yoff: yoff,
    }
    if empty(arg)
        return dim
    endif
    var parts: list<string> = matchlist(arg,
           '^\s*\([0-9]\+%\=\)\='
        .. '\([+-][0-9]\+%\=\)\='
        .. '\%('
        ..     'x\([0-9]\+%\=\)\='
        ..     '\([+-][0-9]\+%\=\)\='
        .. '\)\='
        .. '\s*$')
    if empty(parts)
        echohl WarningMsg
        echo 'Invalid dimension expression: ' .. arg
        echohl None
        return {}
    endif
    if !empty(parts[1])
        dim.width = Relsz(parts[1], &columns)
    endif
    if !empty(parts[2])
        dim.xoff = Relsz(parts[2], &columns)
    endif
    if !empty(parts[3])
        dim.height = Relsz(parts[3], &lines)
    endif
    if !empty(parts[4])
        dim.yoff = Relsz(parts[4], &lines)
    endif
    return dim
enddef

