" vim:tabstop=2:shiftwidth=2:expandtab:textwidth=99
" VimRoam autoload plugin file
" Description: Path manipulation functions
" Home: https://github.com/jeffmm/vimroam/



" Unixify path
function! s:unixify(path) abort
    return substitute(a:path, '\', '/', 'g')
endfunction


" Windowsify path
function! s:windowsify(path) abort
    return substitute(a:path, '/', '\', 'g')
endfunction


" Define os specific path convertion
if vimroam#u#is_windows()
  function! s:osxify(path) abort
    return s:windowsify(a:path)
  endfunction
else
  function! s:osxify(path) abort
    return s:unixify(a:path)
  endfunction
endif


" Remove last path delimitator (slash or backslash)
function! vimroam#path#chomp_slash(str) abort
  return substitute(a:str, '[/\\]\+$', '', '')
endfunction


" Define: path-compare function, either case-sensitive or not, depending on OS.
if vimroam#u#is_windows()
  function! vimroam#path#is_equal(p1, p2) abort
    return a:p1 ==? a:p2
  endfunction
else
  function! vimroam#path#is_equal(p1, p2) abort
    return a:p1 ==# a:p2
  endfunction
endif


" Collapse sections like /a/b/../c to /a/c and /a/b/./c to /a/b/c
function! vimroam#path#normalize(path) abort
  let path = a:path
  while 1
    let intermediateResult = substitute(path, '/[^/]\+/\.\.', '', '')
    let result = substitute(intermediateResult, '/\./', '/', '')
    if result ==# path
      break
    endif
    let path = result
  endwhile
  return result
endfunction


" Normalize path: \ -> / &&  /// -> / && resolve(symlinks)
function! vimroam#path#path_norm(path) abort
  " return if scp
  if a:path =~# '^scp:' | return a:path | endif
  " convert backslash to slash
  let path = substitute(a:path, '\', '/', 'g')
  " treat multiple consecutive slashes as one path separator
  let path = substitute(path, '/\+', '/', 'g')
  " ensure that we are not fooled by a symbolic link
  return resolve(path)
endfunction


" Check if link is to a directory
function! vimroam#path#is_link_to_dir(link) abort
  " It should be ended with \ or /.
  return a:link =~# '\m[/\\]$'
endfunction


" Get absolute path <- path relative to current file
function! vimroam#path#abs_path_of_link(link) abort
  return vimroam#path#normalize(expand('%:p:h').'/'.a:link)
endfunction


" Returns: longest common path prefix of 2 given paths.
" Ex: '~/home/usrname/wiki', '~/home/usrname/wiki/shmiki' => '~/home/usrname/wiki'
function! vimroam#path#path_common_pfx(path1, path2) abort
  let p1 = split(a:path1, '[/\\]', 1)
  let p2 = split(a:path2, '[/\\]', 1)

  let idx = 0
  let minlen = min([len(p1), len(p2)])
  while (idx < minlen) && vimroam#path#is_equal(p1[idx], p2[idx])
    let idx = idx + 1
  endwhile
  if idx == 0
    return ''
  else
    return join(p1[: idx-1], '/')
  endif
endfunction


" Convert path -> full resolved slashed path
function! vimroam#path#wikify_path(path) abort
  let result = resolve(fnamemodify(a:path, ':p'))
  if vimroam#u#is_windows()
    let result = substitute(result, '\\', '/', 'g')
  endif
  let result = vimroam#path#chomp_slash(result)
  return result
endfunction


" Return: Current file path relative
function! vimroam#path#current_wiki_file() abort
  return vimroam#path#wikify_path(expand('%:p'))
endfunction


" Return: the relative path from a:dir to a:file
function! vimroam#path#relpath(dir, file) abort
  " Check if dir here ('.') -> return file
  if empty(a:dir) || a:dir =~# '^\.[/\\]\?$'
    return a:file
  endif
  " Unixify && Expand in
  let s_dir = s:unixify(expand(a:dir))
  let s_file = s:unixify(expand(a:file))

  " Split path
  let dir = split(s_dir, '/')
  let file = split(s_file, '/')

  " Shorten loop till equality
  while (len(dir) > 0 && len(file) > 0) && vimroam#path#is_equal(dir[0], file[0])
    call remove(dir, 0)
    call remove(file, 0)
  endwhile

  " Return './' if nothing left
  if empty(dir) && empty(file)
    return s:osxify('./')
  endif

  " Build path segment
  let segments = []
  for segment in dir
    let segments += ['..']
  endfor
  for segment in file
    let segments += [segment]
  endfor

  " Join segments
  let result_path = join(segments, '/')
  if a:file =~# '\m/$'
    let result_path .= '/'
  endif

  return result_path
endfunction


" Mkdir:
" If the optional argument provided and nonzero,
" it will ask before creating a directory
" Returns: 1 iff directory exists or successfully created
function! vimroam#path#mkdir(path, ...) abort
  let path = expand(a:path)

  if path =~# '^scp:'
    " we can not do much, so let's pretend everything is ok
    return 1
  endif

  if isdirectory(path)
    return 1
  else
    if !exists('*mkdir')
      return 0
    endif

    let path = vimroam#path#chomp_slash(path)
    if vimroam#u#is_windows() && !empty(vimroam#vars#get_global('w32_dir_enc'))
      let path = iconv(path, &encoding, vimroam#vars#get_global('w32_dir_enc'))
    endif

    if a:0 && a:1 && input('VimRoam: Make new directory: '.path.": [y]es/[N]o? ") !~? '^y'
      return 0
    endif

    call mkdir(path, 'p')
    return 1
  endif
endfunction


" Check: if path is absolute
function! vimroam#path#is_absolute(path) abort
  if vimroam#u#is_windows()
    return a:path =~? '\m^\a:'
  else
    return a:path =~# '\m^/\|\~/'
  endif
endfunction


" Combine: a directory and a file into one path, doesn't generate duplicate
" path separator in case the directory is also having an ending / or \. This
" is because on windows ~\vimroam//.tags is invalid but ~\vimroam/.tags is a
" valid path.
if vimroam#u#is_windows()
  function! vimroam#path#join_path(directory, file) abort
    let directory = vimroam#path#chomp_slash(a:directory)
    let file = substitute(a:file, '\m^[\\/]\+', '', '')
    return directory . '/' . file
  endfunction
else
  function! vimroam#path#join_path(directory, file) abort
    let directory = substitute(a:directory, '\m/\+$', '', '')
    let file = substitute(a:file, '\m^/\+', '', '')
    return directory . '/' . file
  endfunction
endif
