" plugin/qnote.vim
if exists("g:loaded_qnote")
  echo "qnote.nvim déjà chargé"
  finish
endif
let g:loaded_qnote = 1

command! Qnote lua require("qnote").hello()
echo "qnote.nvim chargé"
