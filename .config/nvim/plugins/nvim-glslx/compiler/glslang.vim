" :compiler glslang
" Lets `:make %` run glslangValidator against the current shader file.

if exists('current_compiler')
  finish
endif
let current_compiler = 'glslang'

if exists(':CompilerSet') != 2
  command -nargs=* CompilerSet setlocal <args>
endif

if !exists('g:glslang_makeprg')
  let g:glslang_makeprg = 'glslangValidator %'
endif

execute 'CompilerSet makeprg=' . escape(g:glslang_makeprg, ' \|"')

" glslangValidator output:  ERROR: 0:LINE: 'name' : message
CompilerSet errorformat=%trror:\ %f:%l:\ %m,
                     \%tarning:\ %f:%l:\ %m,
                     \%trror:\ 0:%l:\ %m,
                     \%tarning:\ 0:%l:\ %m,
                     \%f:%l:\ %m
