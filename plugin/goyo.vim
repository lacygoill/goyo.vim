if exists('g:loaded_goyo')
    finish
endif
let g:loaded_goyo = 1

com! -nargs=? -bar -bang Goyo call goyo#execute(<bang>0, <q-args>)
