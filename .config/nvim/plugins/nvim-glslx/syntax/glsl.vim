" Syntax overlay for OpenGL GLSL buffers managed by nvim-glslx.
"
" This file is loaded after Vim's built-in syntax/glsl.vim (Neovim ships
" with one). It adds matches for the function-style #include directive
" forms accepted by the validator's preprocessor:
"
"   #include("foo.glsl");
"   #include('foo.glsl');
"
" The native form (#include "foo.glsl") is already covered by the built-in
" GLSL syntax. We do NOT set b:current_syntax so the built-in file runs
" alongside us.

syntax match glslIncludeKeyword /^\s*#\s*include\>/ nextgroup=glslIncludeArgs skipwhite
syntax region glslIncludeArgs matchgroup=glslIncludeParen start=/(/ end=/)/ contained contains=glslIncludeString
syntax region glslIncludeString start=/"/ skip=/\\"/ end=/"/ contained
syntax region glslIncludeString start=/'/ skip=/\\'/ end=/'/ contained

highlight default link glslIncludeKeyword PreProc
highlight default link glslIncludeParen   PreProc
highlight default link glslIncludeString  String
