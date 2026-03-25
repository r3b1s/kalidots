
"""""""""""""""""""""
""""" <LEADERS> """""
"""""""""""""""""""""




""""""""""""""""""""""
""""" NAVIGATION """""
""""""""""""""""""""""

" ~~Have j and k navigate visual lines rather than logical ones.~~
" Have j and k center the display vertically.
noremap j gjzz
noremap k gkzz

" Have Up and Down arrows navigate visual lines rather than logical ones.
" Also have them center the display vertically.
noremap <Up> g<Up>zz
noremap <Down> g<Down>zz

" Have ctrl-u and ctrl-d center the display vertically
noremap <C-u> <C-u>zz
noremap <C-d> <C-d>zz

" Have { and } center the display vertically
noremap { {zz
noremap } }zz

" Have gg and G center the display vertically
noremap gg ggzz
noremap G Gzz

" Have insertion of new lines center the display vertically
noremap o o<Esc>zzI
noremap O O<Esc>zzI

" Have n and N center the display vertically after search navigation.
noremap n nzz
noremap N Nzz

" Have *, #, g*, and g# center the display vertically after searching for the word under the cursor.
noremap * *zz
noremap # #zz
noremap g* g*zz
noremap g# g#zz

" Have H and L center the display vertically after moving to the top or bottom of the screen.
noremap H Hzz
noremap L Lzz

" Have % center the display vertically after matching brackets.
noremap % %zz

" Have gd and gD center the display vertically after going to definitions.
noremap gd gdzz
noremap gD gDzz

" Have ]] and [[ center the display vertically after navigating to the next or previous section.
noremap ]] ]]zz
noremap [[ [[zz

" Have ][ and [] center the display vertically after navigating to the start or end of a section.
noremap ][ ][zz
noremap [] []zz

" Have g; and g, center the display vertically after navigating the change list.
noremap g; g;zz
noremap g, g,zz


""""""""""""""""
""""" MISC """""
""""""""""""""""

" Quickly remove search highlights
nmap <F9> :nohl

" Yank to system clipboard
set clipboard=unnamed

" Remove any vim bindings for ctrl+c in Normal & Insert modes,
" so normal ctrl+c copy works across each mode.
unmap <C-c>
iunmap <C-c>
