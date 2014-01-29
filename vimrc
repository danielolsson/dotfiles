" from http://stackoverflow.com/questions/5375240/a-more-useful-statusline-in-vim:
"hi User1 guifg=#eea040 guibg=#222222
"hi User2 guifg=#dd3333 guibg=#222222
"hi User3 guifg=#ff66ff guibg=#222222
"hi User4 guifg=#a0ee40 guibg=#222222
"hi User5 guifg=#eeee40 guibg=#222222
"
"set statusline=
"set statusline +=%1*\ %n\ %*            "buffer number
"set statusline +=%5*%{&ff}%*            "file format
"set statusline +=%3*%y%*                "file type
"set statusline +=%4*\ %<%F%*            "full path
"set statusline +=%2*%m%*                "modified flag
"set statusline +=%1*%=%5l%*             "current line
"set statusline +=%2*/%L%*               "total lines
"set statusline +=%1*%4v\ %*             "virtual column number
"set statusline +=%2*0x%04B\ %*          "character under cursor

set rtp+=~/dotfiles/powerline/powerline/bindings/vim
"python from powerline.vim import setup as powerline_setup
"python powerline_setup()
"python del powerline_setup

"set guifont=Menlo\ for\ Powerline
set guifont=Menlo
let g:Powerline_symbols = 'fancy'

colorscheme desert256
set laststatus=2
"highlight OverLength ctermbg=darkred ctermfg=white guibg=#FFD9D9
highlight OverLength ctermbg=52 ctermfg=white guibg=#FFD9D9
match OverLength /\%81v.\+/
highlight ColorColumn ctermbg=52 guibg=#FFD9D9
set colorcolumn=80

" Treat .hql files as SQL for syntax highlighting
au BufNewFile,BufRead *.hql set filetype=sql

" vim -b : edit binary using xxd-format!
augroup Binary
  au!
  au BufReadPre  *.bin let &bin=1
  au BufReadPost *.bin if &bin | %!xxd
  au BufReadPost *.bin set ft=xxd | endif
  au BufWritePre *.bin if &bin | %!xxd -r
  au BufWritePre *.bin endif
  au BufWritePost *.bin if &bin | %!xxd
  au BufWritePost *.bin set nomod | endif
augroup END
set modeline
