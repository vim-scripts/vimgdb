"""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Vim plugin for interface to gdb from cterm
" Last change: 2010 Mar 29
" Maintainer: M Sureshkumar (m.sureshkumar@yahoo.com)
"
" Feedback welcome.
"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Prevent multiple loading, allow commenting it out
if exists("loaded_vimgdb")
	finish
endif

let loaded_vimgdb = 1
let s:vimgdb_running = 0
let s:gdb_win_hight = 10
let s:gdb_buf_name = "__GDB_WINDOW__"
let s:cur_line_id = 9999
let s:prv_line_id = 9998
let s:max_break_point = 0
let s:gdb_client = "vimgdb_msg"

" This used to be in Gdb_interf_init, but older vims crashed on it
highlight DebugBreak guibg=darkred guifg=white ctermbg=darkred ctermfg=white
highlight DebugStop guibg=lightgreen guifg=white ctermbg=lightgreen ctermfg=white
sign define breakpoint linehl=DebugBreak
sign define current linehl=DebugStop

" Get ready for communication
function! Gdb_interf_init()

	call s:Gdb_shortcuts()

	"command -nargs=+ Gdb	:call Gdb_command(<q-args>, v:count)

    let bufnum = bufnr(s:gdb_buf_name)

    if bufnum == -1
        " Create a new buffer
        let wcmd = s:gdb_buf_name
    else
        " Edit the existing buffer
        let wcmd = '+buffer' . bufnum
    endif

    " Create the tag explorer window
    exe 'silent!  botright ' . s:gdb_win_hight . 'split ' . wcmd

    " Mark the buffer as a scratch buffer
    setlocal buftype=nofile
    setlocal bufhidden=delete
    setlocal noswapfile
    setlocal wrap
    setlocal nobuflisted
    setlocal nonumber

    augroup VimGdbAutoCommand
	autocmd WinEnter <buffer> call s:EnterGdbBuf()
	autocmd WinLeave <buffer> stopi
	autocmd BufUnload <buffer> call s:Gdb_interf_close()
    augroup end

    inoremap <buffer> <silent> <CR> <ESC>o<ESC>:call <SID>Gdb_command(getline(line(".")-1))<CR>
	inoremap <buffer> <silent> <TAB> <C-P>
	"nnoremap <buffer> <silent> : <C-W>p:

	start
	let s:vimgdb_running = 1

	"wincmd p
endfunction

function s:EnterGdbBuf()
	if !s:vimgdb_running
		return
	endif
" if(winnr("$") == 1)
" 	quit
" endif
	$
	if ! (getline(".") =~ '^\s*$')
		normal o
	endif
	start
endfunction

function s:Gdb_interf_close()
	if !s:vimgdb_running
		return
	endif

	let s:vimgdb_running = 0
	sign unplace *
	let s:Breakpoint = {}
	let s:cur_line_id = 9999
	let s:prv_line_id = 9998

	" If gdb window is open then close it.
	let winnum = bufwinnr(s:gdb_buf_name)
	if winnum != -1
		exe winnum . 'wincmd w'
		quit
	endif

    silent! autocmd! VimGdbAutoCommand
endfunction

function s:Gdb_Disp_Line(file, line)
	let cur_win = winnr()
	let gdb_win = bufwinnr(s:gdb_buf_name)

	if cur_win == gdb_win
		wincmd p
	endif

	if bufname("%") != a:file
		if !bufexists(a:file)
			if !filereadable(a:file)
				return
			endif
			execute 'e +set\ nomodifiable '.a:file
		else
			execute 'b ' . bufname(a:file)
		endif
	endif

	"silent! foldopen!
	execute a:line
	call winline()
	execute cur_win.'wincmd w'
endfunction

function s:Gdb_Bpt(id, file, line)
	call s:Gdb_Disp_Line(a:file, a:line)
	execute "sign unplace ". a:id
	execute "sign place " .  a:id ." name=breakpoint line=".a:line." buffer=".bufnr(a:file)
	let s:BptList_{a:id}_file = bufname(a:file)
	let s:BptList_{a:id}_line = a:line
	if a:id > s:max_break_point
		let s:max_break_point = a:id
	endif
endfunction

function s:Gdb_NoBpt(id)
	if(exists('s:BptList_'. a:id . '_file'))
		unlet s:BptList_{a:id}_file
		unlet s:BptList_{a:id}_line

		if a:id == s:max_break_point
			let s:max_break_point = a:id - 1
		endif

		execute "sign unplace ". a:id
	endif
endfunction

function s:Gdb_CurrFileLine(file, line)
	call s:Gdb_Disp_Line(a:file, a:line)

	let temp = s:cur_line_id
	let s:cur_line_id = s:prv_line_id
	let s:prv_line_id = temp

	" place the next line before unplacing the previous 
	" otherwise display will jump
	execute "sign place " .  s:cur_line_id ." name=current line=".a:line." file=".a:file
	execute "sign unplace ". s:prv_line_id
endf

function s:Gdb_command(cmd)

	if s:vimgdb_running == 0
		echo "VIMGDB is not running"
		return
	endif

	if match (a:cmd, '^\s*$') != -1
		return
	endif

	let cur_win = winnr()
	let gdb_win = bufwinnr(s:gdb_buf_name)

	let out_count = 0

	let lines = system(s:gdb_client . " \"" . a:cmd . "\"")

	let index = 0
	let length = strlen(lines)
	while index < length
		let new_index = match(lines, '\n', index)
		if new_index == -1 
			let new_index = length
		endif
		let len = new_index - index
		let line = strpart(lines,index, len)
		let index = new_index + 1
		if line =~ '^Breakpoint \([0-9]\+\) at 0x.*:'
			let cmd = substitute(line, 
						\ '^Breakpoint \([0-9]\+\) at 0x.*: file \([^,]\+\), line \([0-9]\+\).*', 
						\ 's:Gdb_Bpt(\1,"\2",\3)', '')
		elseif line =~ '^Deleted breakpoint \([0-9]\+\)'
			let cmd = substitute(line, '^Deleted breakpoint \([0-9]\+\).*', 's:Gdb_NoBpt(\1)', '')
		elseif line =~ "^\032\032" . '[^:]*\:[0-9]\+'
			let cmd = substitute(line, "^\032\032" . '\([^:]*\):\([0-9]\+\).*', 's:Gdb_CurrFileLine("\1", \2)', '')
		elseif line =~ '^The program is running\.  Exit anyway'
			let cmd = 's:Gdb_interf_close()'
		else
			if (!(line =~ '^(gdb)')) && (! (line =~ '^\s*$'))
				let output_{out_count} = line
				let out_count = out_count + 1
			endif
			continue
		endif
		exec 'call ' . cmd
	endwhile

	if out_count > 0 && s:vimgdb_running
		if(gdb_win != -1)
			if(gdb_win != cur_win)
				exec gdb_win . 'wincmd w'
			endif

			if getline("$") =~ '^\s*$'
				$delete
			endif
			let index = 0
			while index < out_count
				call append(line("$"), output_{index})
				let index = index + 1
			endwhile
			$
			call winline()
			if cur_win != winnr()
				exec cur_win . 'wincmd w'
			endif
		endif
	endif

	if gdb_win == winnr()
		call s:EnterGdbBuf()
	endif

endfun

" Toggle breakpoints
function s:Gdb_togglebreak(name, line)
	let found = 0
	let bcount = 0

	while  bcount <= s:max_break_point
		if exists("s:BptList_".bcount."_file")
			if bufnr(s:BptList_{bcount}_file) == bufnr(a:name) && s:BptList_{bcount}_line == a:line
				let found = 1
				break
			endif
		endif
		let bcount = bcount + 1
	endwhile

	if found == 1
		call s:Gdb_command("clear ".a:name.":".a:line)
	else
		call s:Gdb_command("break ".a:name.":".a:line)
	endif
endfun

function s:Gdb_shortcuts()
	nmap <silent> <F9>	 :call <SID>Gdb_togglebreak(bufname("%"), line("."))<CR>
	nmap <silent> <F6>   :call <SID>Gdb_command("run")<CR>
	nmap <silent> <F7>	 :call <SID>Gdb_command("step")<CR>
	nmap <silent> <F8>	 :call <SID>Gdb_command("next")<CR>
	nmap <silent> <F5> 	 :call <SID>Gdb_command("continue")<CR>
	nmap <silent> <C-P>	 :call <SID>Gdb_command("print <C-R><C-W>")<CR> 
	vmap <silent> <C-P>	 "vy:call <SID>Gdb_command("print <C-R>v")<CR>
endfunction
