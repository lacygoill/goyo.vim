vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Mappings {{{1

# Add empty lines  above and below the  selection so that it's  the only visible
# text in the buffer; like if it was taking vacation, alone on an island.
xnoremap <unique> <Space>gg <C-\><C-N><Cmd>call goyo#island()<CR>

# If you have weird thick borders around the window (especially visible in a light colorscheme):{{{
#
# You need to temporarily disable `'termguicolors'`, before running `:Goyo`.
# The issue  is specific to urxvt.   I can't reproduce in  other terminals, like
# xterm and st.
#}}}

# FIXME: If I press `SPC gg` in gui, tmux status line gets hidden.  It should stay visible.
# FIXME: If I press  `SPC gg` in an  unzoomed tmux pane, then press  it again to
# leave goyo mode, the pane is zoomed.  The zoomed state should be preserved.
nnoremap <unique> <Space>gg <Cmd>call goyo#start()<CR>
nnoremap <unique> <Space>gG <Cmd>call goyo#start(v:false)<CR>

# Commands {{{1

# TODO: Implement a version of the command in which no text is "dimmed".
# All the text is in black; but the  status lines and all the rest of the visual
# clutter is still removed.
# Or, implement a mapping which would cycle between different submodes of the goyo mode:
#
#    - no syntax highlighting, no dimming
#    - no syntax highlighting, dimming
#    - syntax highlighting, no dimming
#    - syntax highlighting, dimming
#    ...
command -nargs=? -bar -bang Goyo goyo#execute(<bang>0, <q-args>)

# Autocmds {{{1

augroup MyGoyo | autocmd!
    autocmd User GoyoEnter goyo#enter()
    autocmd User GoyoLeave goyo#leave()
augroup END

