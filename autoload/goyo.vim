vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Interface {{{1
def goyo#execute(bang: bool, dim: string) #{{{2
# "dim" = dimensions

    # I'm frequently pressing `zz` when entering goyo mode.
    # Might as well make `:Goyo` do it automatically for me.
    norm! zz
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

def goyo#start(how: string) #{{{2
    with_highlighting = how == 'with_highlighting'
    exe 'Goyo' .. (!exists('#goyo') ? ' 110' : '!')
enddef

def goyo#enter() #{{{2
    # Is inspected by other plugins to adapt their behavior.
    # E.g.: vim-toggle-settings (mappings toggling `'cul'`).
    g:in_goyo_mode = true
    sil system('tmux set status off')
    # FIXME: If we have 2 tmux panes in the same window, Vim is one of them, and
    # it's not zoomed, when we start goyo mode, we see much less text as usual.
    # If we have 2 vertical panes, the lines are shorter.
    # If we have 2 horizontal panes, there are fewer lines.
    sil system('[[ $(tmux display -p "#{window_zoomed_flag}") -eq 0 ]] && tmux resizep -Z')
    set noshowcmd

    [winid_save, bufnr_save] = [win_getid(), bufnr('%')]
    [cocu_save, cole_save] = [&l:cocu, &l:cole]
    setl cocu=nc cole=3

    var pos: list<number> = getcurpos()
    # The new window  created by `:tab sp` inherits the  window-local options of
    # the original window.  But `:tab sp`  doesn't fire `BufWinEnter` so we lose
    # our position in the changelist.
    do <nomodeline> BufWinEnter
    setpos('.', pos)

    augroup MyGoyo
        au! * <buffer>
        # make sure cursor is not on leading whitespace
        au CursorHold <buffer> if getline('.')->match('^\s*\%' .. col('.') .. 'c\s') >= 0
            |     exe 'norm! _'
            | endif
        # clear possible error message from command-line (e.g. `E486`)
        au CursorHold <buffer> echo
    augroup END
    # The autocmd doesn't work initially, probably because `CursorHold` has already been fired.{{{
    #
    # We could run `do CursorHold` now, but I prefer `norm! _`:
    # fewer side effects, and position the cursor in a known location right from
    # the start (helpful with an underline cusor which is harder to spot).
    #}}}
    norm! _

    auto_open_fold_was_enabled = true
    if !exists('b:auto_open_fold_mappings')
        auto_open_fold_was_enabled = false
        toggleSettings#autoOpenFold(true)
    endif

    # We want to be able to read code blocks in our notes (and probably other syntax groups).
    if &ft == 'markdown'
        return
    endif

    Limelight

    if !with_highlighting
        # TODO: We need to ignore other highlight groups.{{{
        #
        # When we're in goyo mode, usually, we're only interested in the code.
        # Anything else should be ignored.
        # Many HGs are missing from the following list.
        #
        # I guess most (all?) the HGs we still want to ignore are defined in:
        #
        #     ~/.vim/plugged/vim-lg-lib/autoload/lg/styledComment.vim
        #
        # Problem: If we remove a  highlight group in `styledComment.vim`, we'll
        # need to remove it here, and vice versa; duplication issue.
        #}}}
        # TODO: It seems that we don't need to reset the HGs once we leave goyo mode.{{{
        #
        # How does it work? Does goyo reload the colorscheme?
        # Make sure the highlighting is properly restored when we leave goyo mode.
        #}}}
        var highlight_groups: list<string> =<< trim END
            CommentItalic
            CommentUnderlined
            CommentPreProc
            Folded
            Todo
            commentCodeSpan
            markdownBlockquote
            markdownListItem
            markdownListItemCodeSpan
            markdownOption
            markdownPointer
            markdownRule
        END
        if &ft != 'help'
            highlight_groups += ['Comment']
        endif
        for group in highlight_groups
            exe 'hi! link ' .. group .. ' Ignore'
        endfor

        highlight_groups =<< trim END
            Conditional
            Constant
            Delimiter
            Function
            Identifier
            Keyword
            MatchParen
            Number
            Operator
            PreProc
            Special
            Statement
            String
            Type
            snipSnippet
        END
        for group in highlight_groups
            exe 'hi ' .. group .. ' term=NONE cterm=NONE ctermfg=NONE ctermbg=NONE gui=NONE guifg=NONE guibg=NONE'
        endfor
    endif
enddef

var cocu_save: string
var cole_save: number
var winid_save: number
var bufnr_save: number
var with_highlighting: bool
var auto_open_fold_was_enabled: bool

def goyo#leave() #{{{2
    unlet! g:in_goyo_mode

    sil system('tmux set status on')
    sil system('[[ $(tmux display -p "#{window_zoomed_flag}") -eq 0 ]] && tmux resizep -Z')

    set showcmd
    if winbufnr(winid_save) == bufnr_save
        var tabnr: number
        var winnr: number
        [tabnr, winnr] = win_id2tabwin(winid_save)
        settabwinvar(tabnr, winnr, '&cocu', cocu_save)
        settabwinvar(tabnr, winnr, '&cole', cole_save)
    endif
    cocu_save = ''
    cole_save = 0
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
    # Once you've refactored all `:wincmd` into `win_execute()`, remove the next `:do`.
    #}}}
    do <nomodeline> WinEnter

    au! MyGoyo * <buffer>
    sil! aug! MyGoyo
    #  │
    #  └ `:h W19`

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
        keepj keepp :'>+s/^\%(\_s*\n\)\+/\r/e
        # same thing above
        # The order of removal is important.{{{
        #
        # We need to remove the empty lines below, before the ones above.
        # That is because removing the lines  above will change the addresses of
        # the line below.
        #}}}
        keepj keepp :'<?^\s*\S?+s/^\%(\_s*\n\)\+/\r/e
        # the mark set on the start of  the selection has been moved to the next line;
        # restore it
        :'<-mark <
    else
        # add empty lines to clear the view
        var cnt: number = winheight(0) / 2
        repeat([''], cnt)->append(line("'<") - 1)
        repeat([''], cnt)->append(line("'>"))
    endif
    norm! '<zz
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
    exe printf('hi %s %s%s=%s', group, gui ? 'gui' : 'cterm', attr, color)
enddef

def Blank(repel: string) #{{{2
    if bufwinnr(t:goyo_pads.r) <= bufwinnr(t:goyo_pads.l) + 1
    || bufwinnr(t:goyo_pads.b) <= bufwinnr(t:goyo_pads.t) + 3
        GoyoOff()
    endif
    exe 'wincmd ' .. repel
enddef

def InitPad(command: string): number #{{{2
    exe command
    setl buftype=nofile bufhidden=wipe nomodifiable nobuflisted noswapfile
        \ nonu nocul nocursorcolumn winfixwidth winfixheight
    &l:stl = ' '
    setl nornu
    setl colorcolumn=
    var bufnr: number = winbufnr(0)
    wincmd p
    return bufnr
enddef

def SetupPad( #{{{2
    bufnr: number,
    vert: number,
    size: number,
    repel: string
)
    var win: number = bufwinnr(bufnr)
    exe ':' .. win .. 'wincmd w'
    # TODO: I think  this doesn't work  as expected  for the height,  because of
    # `vim-window` which maximizes windows' height.
    noa exe (vert ? 'vertical ' : '') .. 'resize ' .. max([0, size])
    augroup goyop
        BlankRef = function(Blank, [repel])
        autocmd WinEnter,CursorMoved <buffer> ++nested BlankRef()
        au WinLeave <buffer> HideStatusline()
    augroup END

    # to hide scrollbars of pad windows in the GUI
    var diff: number = winheight(0) - line('$') - (has('gui_running') ? 2 : 0)
    if diff > 0
        setl modifiable
        repeat([''], diff)->append(0)
        normal! gg
        setl nomodifiable
    endif
    wincmd p
enddef
var BlankRef: func

def ResizePads() #{{{2
    augroup goyop | au!
    augroup END

    t:goyo_dim.width = Const(t:goyo_dim.width, 2, &columns)
    t:goyo_dim.height = Const(t:goyo_dim.height, 2, &lines)

    var vmargin: number = max([0, (&lines - t:goyo_dim.height) / 2 - 1])
    var yoff: number = Const(t:goyo_dim.yoff, - vmargin, vmargin)
    var top: number = vmargin + yoff
    var bot: number = vmargin - yoff - 1
    SetupPad(t:goyo_pads.t, 0, top, 'j')
    SetupPad(t:goyo_pads.b, 0, bot, 'k')

    var nwidth: number = max([line('$')->len() + 1, &numberwidth])
    var width: number = t:goyo_dim.width + (&number ? nwidth : 0)
    var hmargin: number = max([0, (&columns - width) / 2 - 1])
    var xoff: number = Const(t:goyo_dim.xoff, - hmargin, hmargin)
    SetupPad(t:goyo_pads.l, 1, hmargin + xoff, 'l')
    SetupPad(t:goyo_pads.r, 1, hmargin - xoff, 'h')
enddef

def Tranquilize() #{{{2
    var bg: string = GetColor('Normal', 'bg#')
    for grp in ['NonText', 'FoldColumn', 'ColorColumn', 'VertSplit',
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
    &l:stl = ' '
enddef

def HideLinenr() #{{{2
    setl nonu
    setl nornu
    setl colorcolumn=
enddef

def MapsNop(): list<string> #{{{2
    var mapped: list<string> = ['R', 'H', 'J', 'K', 'L', '|', '_']
        ->filter((_, v: string): bool => maparg("\<c-w>" .. v, 'n')->empty())
    for c in mapped
        exe 'nno <c-w>' .. escape(c, '|') .. ' <nop>'
    endfor
    return mapped
enddef

def MapsResize(): list<string> #{{{2
    var commands: dict<string> = {
        '=': '<cmd>let t:goyo_dim = <sid>ParseArg(t:goyo_dim_expr) <bar> call <sid>ResizePads()<cr>',
        '>': '<cmd>let t:goyo_dim.width = winwidth(0) + 2 * v:count1 <bar> call <sid>ResizePads()<cr>',
        '<': '<cmd>let t:goyo_dim.width = winwidth(0) - 2 * v:count1 <bar> call <sid>ResizePads()<cr>',
        '+': '<cmd>let t:goyo_dim.height += 2 * v:count1 <bar> call <sid>ResizePads()<cr>',
        '-': '<cmd>let t:goyo_dim.height -= 2 * v:count1 <bar> call <sid>ResizePads()<cr>'
    }
    var mapped: list<string> = keys(commands)
        ->filter((_, v: string): bool => maparg("\<c-w>" .. v, 'n')->empty())
    for c in mapped
        exe 'nno <c-w>' .. c .. ' ' .. commands[c]
    endfor
    return mapped
enddef

nno <plug>(goyo-resize) <cmd>call <sid>ResizePads()<cr>

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
    &winheight = max([&winminheight, 1])
    set winminheight=1
    set winheight=1
    set winminwidth=1 winwidth=1
    set laststatus=0
    set showtabline=0
    set noruler
    &fcs ..= ',vert: ,stl: ,stlnc: '
    set sidescroll=1
    set sidescrolloff=0

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

    augroup goyo | au!
        au TabLeave * ++nested GoyoOff()
        au VimResized * ResizePads()
        au ColorScheme * Tranquilize()
        au BufWinEnter * HideLinenr() | HideStatusline()
        au WinEnter,WinLeave * HideStatusline()
    augroup END

    HideStatusline()
    if exists('#User#GoyoEnter')
        do <nomodeline> User GoyoEnter
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
    exe 'au! goyo' | aug! goyo
    exe 'au! goyop' | aug! goyop

    for c in t:goyo_maps
        exe 'nunmap <c-w>' .. escape(c, '|')
    endfor

    var goyo_revert: dict<any> = t:goyo_revert
    var goyo_orig_buffer: number = t:goyo_master
    var lnum: number = line('.')
    var col: number = col('.')

    if tabpagenr() == 1
        tabnew
        normal! gt
        bd
    endif
    tabclose
    exe 'normal! ' .. orig_tab .. 'gt'
    if winbufnr(0) == goyo_orig_buffer
        # Doesn't work if window closed with `q`
        exe printf('normal! %dG%d|', lnum, col)
    endif

    var wmw: number = remove(goyo_revert, 'winminwidth')
    var ww: number = remove(goyo_revert, 'winwidth')
    &winwidth = ww
    &winminwidth = wmw
    var wmh: number = remove(goyo_revert, 'winminheight')
    var wh: number = remove(goyo_revert, 'winheight')
    &winheight = max([wmh, 1])
    &winminheight = wmh
    &winheight = wh

    for [k, v] in items(goyo_revert)
        exe printf('&%s = %s', k, string(v))
    endfor
    # TODO: Why does junegunn re-set the colorscheme?
    #
    # For us, it's helpful,  because we clear some HGs while  in goyo mode, like
    # `PreProc` used to highlight the title of  a comment; and we want them back
    # when when we leave goyo mode.
    exe 'colo ' .. get(g:, 'colors_name', 'default')

    if exists('#User#GoyoLeave')
        do <nomodeline> User GoyoLeave
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

