" plugin/qnote.vim
if exists("g:loaded_qnote")
  finish
endif
let g:loaded_qnote = 1

command! Qnote lua require("qnote").fetch_todos()
