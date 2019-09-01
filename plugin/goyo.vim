if exists('g:loaded_goyo')
    finish
endif
let g:loaded_goyo = 1

" Mappings {{{1

" Add empty lines  above and below the  selection so that it's  the only visible
" text in the buffer; like if it was taking vacation, alone on an island.
xno <silent><unique> <space>gg :<c-u>call goyo#island()<cr>

" If you have weird thick borders around the window (especially visible in a light colorscheme):{{{
"
" You need to temporarily disable `'tgc'`, before running `:Goyo`.
" The  issue is specific  to urxvt. I can't  reproduce in other  terminals, like
" xterm and st.
"}}}

" FIXME: If I press `SPC gg` in gui, tmux status line gets hidden. It should stay visible.
" FIXME: If I press `SPC gg` in an unzoomed tmux pane,  then press it again
" to leave goyo mode, the pane is zoomed. The zoomed state should be preserved.
nno <silent><unique> <space>gg :<c-u>call goyo#start('without_highlighting')<cr>
nno <silent><unique> <space>gG :<c-u>call goyo#start('with_highlighting')<cr>

" Commands {{{1

" TODO: Implement a version of the command in which no text is "dimmed".
" All the text is in black; but the  status lines are still, and all the rest of
" the visual clutter is removed.
com! -nargs=? -bar -bang Goyo call goyo#execute(<bang>0, <q-args>)

" Autocmds {{{1

augroup my_goyo
    au!
    au User GoyoEnter call goyo#enter()
    au User GoyoLeave call goyo#leave()
augroup END

