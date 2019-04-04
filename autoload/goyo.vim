fu! s:const(val, min, max) abort
    return min([max([a:val, a:min]), a:max])
endfu

fu! s:get_color(group, attr) abort
    return synIDattr(synIDtrans(hlID(a:group)), a:attr)
endfu

fu! s:set_color(group, attr, color) abort
    let gui = has('gui_running') || has('termguicolors') && &termguicolors
    exe printf('hi %s %s%s=%s', a:group, gui ? 'gui' : 'cterm', a:attr, a:color)
endfu

fu! s:blank(repel) abort
    if bufwinnr(t:goyo_pads.r) <= bufwinnr(t:goyo_pads.l) + 1
                \ || bufwinnr(t:goyo_pads.b) <= bufwinnr(t:goyo_pads.t) + 3
        call s:goyo_off()
    endif
    exe 'wincmd' a:repel
endfu

fu! s:init_pad(command) abort
    exe a:command
    setl buftype=nofile bufhidden=wipe nomodifiable nobuflisted noswapfile
                \ nonu nocursorline nocursorcolumn winfixwidth winfixheight statusline=\ 
    setl nornu
    setl colorcolumn=
    let bufnr = winbufnr(0)
    exe winnr('#').'wincmd w'
    return bufnr
endfu

fu! s:setup_pad(bufnr, vert, size, repel) abort
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
    exe winnr('#') . 'wincmd w'
endfu

fu! s:resize_pads() abort
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

fu! s:tranquilize() abort
    let bg = s:get_color('Normal', 'bg#')
    for grp in ['NonText', 'FoldColumn', 'ColorColumn', 'VertSplit',
                \ 'StatusLine', 'StatusLineNC', 'SignColumn']
        " -1 on Vim / '' on GVim
        if bg ==# -1 || empty(bg)
            call s:set_color(grp, 'fg', get(g:, 'goyo_bg', 'black'))
            call s:set_color(grp, 'bg', 'NONE')
        else
            call s:set_color(grp, 'fg', bg)
            call s:set_color(grp, 'bg', bg)
        endif
        call s:set_color(grp, '', 'NONE')
    endfor
endfu

fu! s:hide_statusline() abort
    setl statusline=\ 
endfu

fu! s:hide_linenr() abort
    if !get(g:, 'goyo_linenr', 0)
        setl nonu
        setl nornu
    endif
    setl colorcolumn=
endfu

fu! s:maps_nop() abort
    let mapped = filter(['R', 'H', 'J', 'K', 'L', '|', '_'],
                \ "empty(maparg(\"\<c-w>\".v:val, 'n'))")
    for c in mapped
        exe 'nno <c-w>'.escape(c, '|').' <nop>'
    endfor
    return mapped
endfu

fu! s:maps_resize() abort
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

fu! s:goyo_on(dim) abort
    let dim = s:parse_arg(a:dim)
    if empty(dim)
        return
    endif

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

    " New tab
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
    set fillchars+=vert:\ 
    set fillchars+=stl:\ 
    set fillchars+=stlnc:\ 
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
        au TabLeave    *        call s:goyo_off()
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

fu! s:goyo_off() abort
    if !exists('#goyo')
        return
    endif

    " Oops, not this tab
    if !exists('t:goyo_revert')
        return
    endif

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

fu! s:relsz(expr, limit) abort
    if a:expr !~ '%$'
        return str2nr(a:expr)
    endif
    return a:limit * str2nr(a:expr[:-2]) / 100
endfu

fu! s:parse_arg(arg) abort
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

fu! goyo#execute(bang, dim) abort
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
