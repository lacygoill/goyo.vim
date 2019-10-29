fu goyo#island() abort "{{{1
    let should_collapse =
        \    line("'<") > 2 && getline(line("'<")-1) =~# '^\s*$' && getline(line("'<")-2) =~# '^\s*$'
        \ && line("'>") < line('$') - 1 && getline(line("'>")+1) =~# '^\s*$' && getline(line("'>")+2) =~# '^\s*$'
    if should_collapse
        " remove superflous empty lines below
        keepj keepp '>+s/^\%(\_s*\n\)\+/\r/e
        " same thing above
        " The order of removal is important.{{{
        "
        " We need to remove the empty lines below, before the ones above.
        " That is because removing the lines  above will change the addresses of
        " the line below.
        "}}}
        keepj keepp '<?^\s*\S?+s/^\%(\_s*\n\)\+/\r/e
        " the mark set on the start of  the selection has been moved to the next line;
        " restore it
        '<-mark <
    else
        " add empty lines to clear the view
        let cnt = winheight(0)/2
        call append(line("'<")-1, repeat([''], cnt))
        call append(line("'>"), repeat([''], cnt))
    endif
    norm! '<zz
endfu

fu goyo#start(how) abort "{{{1
    let s:with_highlighting = a:how is# 'with_highlighting'
    exe 'Goyo'.(!exists('#goyo') ? ' 110' : '!')
endfu

fu goyo#enter() abort "{{{1
    " Is inspected by other plugins to adapt their behavior.
    " E.g.: vim-toggle-settings (mappings toggling 'cul').
    let g:in_goyo_mode = 1
    sil call system('tmux set status off')
    " FIXME: If we have 2 tmux panes in the same window, Vim is one of them, and
    " it's not zoomed, when we start goyo mode, we see much less text as usual.
    " If we have 2 vertical panes, the lines are shorter.
    " If we have 2 horizontal panes, there are fewer lines.
    sil call system('[[ $(tmux display -p "#{window_zoomed_flag}") -eq 0 ]] && tmux resizep -Z')
    set noshowcmd

    let [s:winid_save, s:bufnr_save] = [win_getid(), bufnr('%')]
    let [s:cocu_save, s:cole_save] = [&l:cocu, &l:cole]
    setl cocu=nc cole=3

    let pos = getcurpos()
    " The new window created by `:tab sp` inherits the window-local options of
    " the original window. But `:tab sp` doesn't fire `BufWinEnter` so we lose
    " our position in the changelist.
    "
    " FIXME: We should  use the function `s:restore_change_position()`  but it's
    " local to `vim-window`.
    sil! exe 'norm! '.(exists('b:my_change_position') ? '99g;' : '99g,')
        \ .(b:my_change_position - 1) .'g,'
    call setpos('.', pos)

    augroup my_goyo
        au! * <buffer>
        " make sure cursor is not on leading whitespace
        au CursorHold <buffer> if match(getline('.'), '^\s*\%'..col('.')..'c\s') >= 0 | exe 'norm! _' | endif
        " clear possible error message from command-line
        au CursorHold <buffer> redraw!
    augroup END
    " The autocmd doesn't work initially, probably because `CursorHold` has already been fired.{{{
    "
    " We could run `do CursorHold` now, but I prefer `norm! _`:
    " less side-effects, and position the cursor  in a known location right from
    " the start (helpful with an underline cusor which is harder to spot).
    "}}}
    norm! _

    let s:auto_open_fold_was_enabled = 1
    if ! exists('b:auto_open_fold_mappings')
        let s:auto_open_fold_was_enabled = 0
        call toggle_settings#auto_open_fold('enable')
    endif

    " We want to be able to read code blocks in our notes (and probably other syntax groups).
    if &ft is# 'markdown' | return | endif

    Limelight

    if ! get(s:, 'with_highlighting', 0)
        " TODO: We need to ignore other highlight groups.{{{
        "
        " When we're in goyo mode, usually, we're only interested in the code.
        " Anything else should be ignored.
        " Many HGs are missing from the following list.
        "
        " I guess most (all?) the HGs we still want to ignore are defined in:
        "
        "     ~/.vim/plugged/vim-lg-lib/autoload/lg/styled_comment.vim
        "
        " Issue: If we  remove a highlight group  in `styled_comment.vim`, we'll
        " need to remove it here, and vice versa; duplication issue.
        "}}}
        " TODO: It seems that we don't need to reset the HGs once we leave goyo mode.{{{
        "
        " How does it work? Does goyo reload the colorscheme?
        " Make sure the highlighting is properly restored when we leave goyo mode.
        "}}}
        let highlight_groups =<< trim END
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
        if &ft isnot# 'help' | let highlight_groups += ['Comment'] | endif
        for group in highlight_groups
            exe 'hi! link '.group.' Ignore'
        endfor

        let highlight_groups =<< trim END
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
            exe 'hi '.group.' term=NONE cterm=NONE ctermfg=NONE ctermbg=NONE gui=NONE guifg=NONE guibg=NONE'
        endfor
    endif
endfu

fu goyo#leave() abort "{{{1
    unlet! g:in_goyo_mode

    sil call system('tmux set status on')
    sil call system('[[ $(tmux display -p "#{window_zoomed_flag}") -eq 0 ]] && tmux resizep -Z')

    set showcmd
    if winbufnr(s:winid_save) == s:bufnr_save
        let [tabnr, winnr] = win_id2tabwin(s:winid_save)
        call settabwinvar(tabnr, winnr, '&cocu', s:cocu_save)
        call settabwinvar(tabnr, winnr, '&cole', s:cole_save)
    endif
    unlet! s:cocu_save s:cole_save s:winid_save s:bufnr_save

    au! my_goyo * <buffer>
    sil! aug! my_goyo
    "  │
    "  └ W19

    Limelight!
    if ! s:auto_open_fold_was_enabled && exists('b:auto_open_fold_mappings')
        call toggle_settings#auto_open_fold('disable')
    endif
endfu

fu s:const(val, min, max) abort "{{{1
    return min([max([a:val, a:min]), a:max])
endfu

fu s:get_color(group, attr) abort "{{{1
    return synIDattr(synIDtrans(hlID(a:group)), a:attr)
endfu

fu s:set_color(group, attr, color) abort "{{{1
    let gui = has('gui_running') || has('termguicolors') && &termguicolors
    exe printf('hi %s %s%s=%s', a:group, gui ? 'gui' : 'cterm', a:attr, a:color)
endfu

fu s:blank(repel) abort "{{{1
    if bufwinnr(t:goyo_pads.r) <= bufwinnr(t:goyo_pads.l) + 1
                \ || bufwinnr(t:goyo_pads.b) <= bufwinnr(t:goyo_pads.t) + 3
        call s:goyo_off()
    endif
    exe 'wincmd' a:repel
endfu

fu s:init_pad(command) abort "{{{1
    exe a:command
    setl buftype=nofile bufhidden=wipe nomodifiable nobuflisted noswapfile
                \ nonu nocul nocursorcolumn winfixwidth winfixheight
    let &l:stl = ' '
    setl nornu
    setl colorcolumn=
    let bufnr = winbufnr(0)
    wincmd p
    return bufnr
endfu

fu s:setup_pad(bufnr, vert, size, repel) abort "{{{1
    let win = bufwinnr(a:bufnr)
    exe win . 'wincmd w'
    exe (a:vert ? 'vertical ' : '').'resize '.max([0, a:size])
    augroup goyop
        exe 'autocmd WinEnter,CursorMoved <buffer> ++nested call s:blank("'.a:repel.'")'
        au WinLeave <buffer> call s:hide_statusline()
    augroup END

    " To hide scrollbars of pad windows in GVim
    let diff = winheight(0) - line('$') - (has('gui_running') ? 2 : 0)
    if diff > 0
        setl modifiable
        call append(0, map(range(1, diff), '""'))
        normal! gg
        setl nomodifiable
    endif
    wincmd p
endfu

fu s:resize_pads() abort "{{{1
    augroup goyop
        au!
    augroup END

    let t:goyo_dim.width = s:const(t:goyo_dim.width, 2, &columns)
    let t:goyo_dim.height = s:const(t:goyo_dim.height, 2, &lines)

    let vmargin = max([0, (&lines - t:goyo_dim.height) / 2 - 1])
    let yoff = s:const(t:goyo_dim.yoff, - vmargin, vmargin)
    let top = vmargin + yoff
    let bot = vmargin - yoff - 1
    call s:setup_pad(t:goyo_pads.t, 0, top, 'j')
    call s:setup_pad(t:goyo_pads.b, 0, bot, 'k')

    let nwidth  = max([len(string(line('$'))) + 1, &numberwidth])
    let width   = t:goyo_dim.width + (&number ? nwidth : 0)
    let hmargin = max([0, (&columns - width) / 2 - 1])
    let xoff    = s:const(t:goyo_dim.xoff, - hmargin, hmargin)
    call s:setup_pad(t:goyo_pads.l, 1, hmargin + xoff, 'l')
    call s:setup_pad(t:goyo_pads.r, 1, hmargin - xoff, 'h')
endfu

fu s:tranquilize() abort "{{{1
    let bg = s:get_color('Normal', 'bg#')
    for grp in ['NonText', 'FoldColumn', 'ColorColumn', 'VertSplit',
                \ 'StatusLine', 'StatusLineNC', 'SignColumn']
        " -1 on Vim / '' on GVim
        if bg == -1 || empty(bg)
            call s:set_color(grp, 'fg', get(g:, 'goyo_bg', 'black'))
            call s:set_color(grp, 'bg', 'NONE')
        else
            call s:set_color(grp, 'fg', bg)
            call s:set_color(grp, 'bg', bg)
        endif
        call s:set_color(grp, '', 'NONE')
    endfor
endfu

fu s:hide_statusline() abort "{{{1
    let &l:stl = ' '
endfu

fu s:hide_linenr() abort "{{{1
    if !get(g:, 'goyo_linenr', 0)
        setl nonu
        setl nornu
    endif
    setl colorcolumn=
endfu

fu s:maps_nop() abort "{{{1
    let mapped = filter(['R', 'H', 'J', 'K', 'L', '|', '_'],
                \ "empty(maparg(\"\<c-w>\".v:val, 'n'))")
    for c in mapped
        exe 'nno <c-w>'.escape(c, '|').' <nop>'
    endfor
    return mapped
endfu

fu s:maps_resize() abort "{{{1
    let commands = {
                \ '=': ':<c-u>let t:goyo_dim = <sid>parse_arg(t:goyo_dim_expr) <bar> call <sid>resize_pads()<cr>',
                \ '>': ':<c-u>let t:goyo_dim.width = winwidth(0) + 2 * v:count1 <bar> call <sid>resize_pads()<cr>',
                \ '<': ':<c-u>let t:goyo_dim.width = winwidth(0) - 2 * v:count1 <bar> call <sid>resize_pads()<cr>',
                \ '+': ':<c-u>let t:goyo_dim.height += 2 * v:count1 <bar> call <sid>resize_pads()<cr>',
                \ '-': ':<c-u>let t:goyo_dim.height -= 2 * v:count1 <bar> call <sid>resize_pads()<cr>'
                \ }
    let mapped = filter(keys(commands), "empty(maparg(\"\<c-w>\".v:val, 'n'))")
    for c in mapped
        exe 'nno <silent> <c-w>'.c.' '.commands[c]
    endfor
    return mapped
endfu

nno <silent> <plug>(goyo-resize) :<c-u>call <sid>resize_pads()<cr>

fu s:goyo_on(dim) abort "{{{1
    let dim = s:parse_arg(a:dim)
    if empty(dim) | return | endif

    let s:orig_tab = tabpagenr()
    let settings =
                \ { 'laststatus':    &laststatus,
                \   'showtabline':   &showtabline,
                \   'fillchars':     &fillchars,
                \   'winminwidth':   &winminwidth,
                \   'winwidth':      &winwidth,
                \   'winminheight':  &winminheight,
                \   'winheight':     &winheight,
                \   'ruler':         &ruler,
                \   'sidescroll':    &sidescroll,
                \   'sidescrolloff': &sidescrolloff
                \ }

    tab split

    let t:goyo_master = winbufnr(0)
    let t:goyo_dim = dim
    let t:goyo_dim_expr = a:dim
    let t:goyo_pads = {}
    let t:goyo_revert = settings
    let t:goyo_maps = extend(s:maps_nop(), s:maps_resize())
    if has('gui_running')
        let t:goyo_revert.guioptions = &guioptions
    endif

    " vim-gitgutter
    let t:goyo_disabled_gitgutter = get(g:, 'gitgutter_enabled', 0)
    if t:goyo_disabled_gitgutter
        sil! GitGutterDisable
    endif

    " vim-signify
    let t:goyo_disabled_signify = exists('b:sy') && b:sy.active
    if t:goyo_disabled_signify
        SignifyToggle
    endif

    call s:hide_linenr()
    " Global options
    let &winheight = max([&winminheight, 1])
    set winminheight=1
    set winheight=1
    set winminwidth=1 winwidth=1
    set laststatus=0
    set showtabline=0
    set noruler
    let &fcs ..= 'vert: ,stl: ,stlnc: '
    set sidescroll=1
    set sidescrolloff=0

    " Hide left-hand scrollbars
    if has('gui_running')
        set guioptions-=l
        set guioptions-=L
    endif

    let t:goyo_pads.l = s:init_pad('vertical topleft new')
    let t:goyo_pads.r = s:init_pad('vertical botright new')
    let t:goyo_pads.t = s:init_pad('topleft new')
    let t:goyo_pads.b = s:init_pad('botright new')

    call s:resize_pads()
    call s:tranquilize()

    augroup goyo
        au!
        au TabLeave    *        ++nested call s:goyo_off()
        au VimResized  *        call s:resize_pads()
        au ColorScheme *        call s:tranquilize()
        au BufWinEnter *        call s:hide_linenr() | call s:hide_statusline()
        au WinEnter,WinLeave *  call s:hide_statusline()
        if has('nvim')
            au TermClose * call feedkeys("\<plug>(goyo-resize)")
        endif
    augroup END

    call s:hide_statusline()
    if exists('g:goyo_callbacks[0]')
        call g:goyo_callbacks[0]()
    endif
    if exists('#User#GoyoEnter')
        doautocmd <nomodeline> User GoyoEnter
    endif
endfu

fu s:goyo_off() abort "{{{1
    if !exists('#goyo') | return | endif

    " Oops, not this tab
    if !exists('t:goyo_revert') | return | endif

    " Clear auto commands
    exe 'au! goyo' | aug! goyo
    exe 'au! goyop' | aug! goyop

    for c in t:goyo_maps
        exe 'nunmap <c-w>'.escape(c, '|')
    endfor

    let goyo_revert             = t:goyo_revert
    let goyo_disabled_gitgutter = t:goyo_disabled_gitgutter
    let goyo_disabled_signify   = t:goyo_disabled_signify
    let goyo_orig_buffer        = t:goyo_master
    let [line, col]             = [line('.'), col('.')]

    if tabpagenr() == 1
        tabnew
        normal! gt
        bd
    endif
    tabclose
    exe 'normal! '.s:orig_tab.'gt'
    if winbufnr(0) == goyo_orig_buffer
        " Doesn't work if window closed with `q`
        exe printf('normal! %dG%d|', line, col)
    endif

    let wmw = remove(goyo_revert, 'winminwidth')
    let ww  = remove(goyo_revert, 'winwidth')
    let &winwidth     = ww
    let &winminwidth  = wmw
    let wmh = remove(goyo_revert, 'winminheight')
    let wh  = remove(goyo_revert, 'winheight')
    let &winheight    = max([wmh, 1])
    let &winminheight = wmh
    let &winheight    = wh

    for [k, v] in items(goyo_revert)
        exe printf('let &%s = %s', k, string(v))
    endfor
    " TODO: Why does junegunn re-set the colorscheme?
    "
    " For us, it's helpful,  because we clear some HGs while  in goyo mode, like
    " `PreProc` used to highlight the title of  a comment; and we want them back
    " when when we leave goyo mode.
    exe 'colo '. get(g:, 'colors_name', 'default')

    if goyo_disabled_gitgutter
        sil! GitGutterEnable
    endif

    if goyo_disabled_signify
        sil! if !b:sy.active
        SignifyToggle
    endif
endif

if exists('g:goyo_callbacks[1]')
    call g:goyo_callbacks[1]()
endif
if exists('#User#GoyoLeave')
    doautocmd User GoyoLeave
endif
endfu

fu s:relsz(expr, limit) abort "{{{1
    if a:expr !~ '%$'
        return str2nr(a:expr)
    endif
    return a:limit * str2nr(a:expr[:-2]) / 100
endfu

fu s:parse_arg(arg) abort "{{{1
    if exists('g:goyo_height') || !exists('g:goyo_margin_top') && !exists('g:goyo_margin_bottom')
        let height = s:relsz(get(g:, 'goyo_height', '85%'), &lines)
        let yoff = 0
    else
        let top = max([0, s:relsz(get(g:, 'goyo_margin_top', 4), &lines)])
        let bot = max([0, s:relsz(get(g:, 'goyo_margin_bottom', 4), &lines)])
        let height = &lines - top - bot
        let yoff = top - bot
    endif

    let dim = { 'width':  s:relsz(get(g:, 'goyo_width', 80), &columns),
                \ 'height': height,
                \ 'xoff':   0,
                \ 'yoff':   yoff }
    if empty(a:arg)
        return dim
    endif
    let parts = matchlist(a:arg, '^\s*\([0-9]\+%\?\)\?\([+-][0-9]\+%\?\)\?\%(x\([0-9]\+%\?\)\?\([+-][0-9]\+%\?\)\?\)\?\s*$')
    if empty(parts)
        echohl WarningMsg
        echo 'Invalid dimension expression: '.a:arg
        echohl None
        return {}
    endif
    if !empty(parts[1]) | let dim.width  = s:relsz(parts[1], &columns) | endif
    if !empty(parts[2]) | let dim.xoff   = s:relsz(parts[2], &columns) | endif
    if !empty(parts[3]) | let dim.height = s:relsz(parts[3], &lines)   | endif
    if !empty(parts[4]) | let dim.yoff   = s:relsz(parts[4], &lines)   | endif
    return dim
endfu

fu goyo#execute(bang, dim) abort "{{{1
    if a:bang
        if exists('#goyo')
            call s:goyo_off()
        endif
    else
        if exists('#goyo') == 0
            call s:goyo_on(a:dim)
        elseif !empty(a:dim)
            if winnr('$') < 5
                call s:goyo_off()
                return goyo#execute(a:bang, a:dim)
            endif
            let dim = s:parse_arg(a:dim)
            if !empty(dim)
                let t:goyo_dim = dim
                let t:goyo_dim_expr = a:dim
                call s:resize_pads()
            endif
        else
            call s:goyo_off()
        end
    end
endfu
