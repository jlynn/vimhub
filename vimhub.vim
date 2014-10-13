" Object for interfacing with github
let s:github = {}
let s:github.api_endpoint = "https://api.github.com"
let s:github.access_token = ""

" Object for interfacing with the local git repo
let s:git = {}

function! s:github.get(path)
    " API get request to the path
    let request_url = self.api_endpoint.a:path.'?access_token='.self.access_token
    let response = webapi#http#get(request_url)
    let result = webapi#json#decode(response.content)

    return result
endfunction

function! s:github.pulls()
    let path = '/repos/hearsaycorp/HearsayLabs/pulls'
    return self.get(path)
endfunction

function! s:github.pull(id)
    let path = '/repos/hearsaycorp/HearsayLabs/pulls/'.a:id
    return self.get(path)
endfunction

function! s:git.has_commit(commit)

    let result = system(fugitive#repo().git_command('name-rev', a:commit))

    if result =~# '^'.a:commit
        return 1
    endif

    return 0

endfunction

function! vimhub#load_prs()

    " Map pr numbers to the pr data
    let b:prs = {}

    let pr_data = s:github.pulls()
    let i = 1

    for pr in pr_data
        let b:prs[pr.number] = pr
        let pr_summary = pr.number." ".pr.user.login." ".pr.title
        call setline(i, pr_summary)
        let i += 1
    endfor

endfunction

function! vimhub#load_pr(id)

    let pr = vimhub#pull(a:id)

    call setline(1, pr.title)
    call setline(2, "")
    call setline(3, pr.body)

endfunction

function! s:LoadInStatus(cmd, buffname, bufftype)
    " Loads status in a new split

    " Create the split
    execute 'split '.a:buffname

    " Delete its contents
    normal! ggdG

    execute 'setlocal filetype='.a:bufftype
    setlocal buftype=nofile

    " Run our command to populate the status buffer
    execute a:cmd

    " Create commands for navigating status window options
    execute 'call s:'.a:bufftype.'_commands()'

endfunction

function! s:pull_requests_commands() abort
    nnoremap <buffer> <silent> d :<C-U>exe <SID>view_diff()<CR>
    nnoremap <buffer> <silent> o :<C-U>exe <SID>view_pull_request()<CR>
    nnoremap <buffer> <silent> r :<C-U>exe <SID>review_pull_request()<CR>
endfunction

function! s:view_diff()
    " Show the diff of the current file for the current pr_info

    let current_file = getline('.')

    let left = fugitive#repo().translate(':/'.b:pr.base.label).'/'.current_file
    let right = fugitive#repo().translate(':/'.b:pr.head.label).'/'.current_file

    execute 'tabedit '.left
    diffthis
    execute 'rightbelow vsplit '.right
    diffthis

endfunction
    
function! s:view_pull_request()
    " Looks at the text on the current line and performs an 'open'
    " command relevant to its contents

    let current_line = getline('.')

    " If this line does not begin with numbers (pull request id)
    if current_line !~# '^\d\{1,\} '
        return
    endif

    let pr_number = matchstr(current_line, '\d\{1,\}')
    let pr = b:prs[pr_number]

    normal! ggdG

    let pr_summary = [pr.title, ""]
    let pr_summary += split(pr.body, '\v[\r\n]+')

    let i = 1
    for line in pr_summary
        call setline(i, line)
        let i += 1
    endfor

endfunction

function! s:review_pull_request()
    " Loads the pull requests changed files in the status window

    let current_line = getline('.')

    " If this line does not begin with numbers (pull request id)
    if current_line !~# '^\d\{1,\} '
        return
    endif

    let pr_number = matchstr(current_line, '\d\{1,\}')
    let b:pr = b:prs[pr_number]

    let pr_files = vimhub#get_pr_files(pr_number)

    normal! ggdG

    let i = 1
    for pr_file in pr_files
        call setline(i, pr_file)
        let i += 1
    endfor

endfunction

function! vimhub#show_pr(id)
    return b:prs[a:id]
endfunction

function! vimhub#show_full_pr(id)
    return s:github:pull(a:id)
endfunction

function! vimhub#get_remote(repo)
    " Get the remote branch for the specified repo

    " Get a list of all remotes that contain repo name
    let cmd = fugitive#repo().git_command('config', '--get-regexp', '^remote', a:repo)
    let remotes = split(system(cmd), '\n')

    if len(remotes) == 0
        return ''
    endif

    " Extract the remote name
    let remote = matchstr(remotes[0], '\v^remote\.\zs[^\.]+')
    return remote

endfunction

function! vimhub#add_remote(name, url)
    echo "adding remote repo ".a:name
    execute system(fugitive#repo().git_command('remote', 'add', a:name, a:url))
endfunction

function! vimhub#fetch_repo(repo)
    " Fetch the repo if we don't have its head

    let remote = vimhub#get_remote(a:repo.owner.login)

    if remote == ""
        let remote = a:repo.owner.login
        execute vimhub#add_remote(remote, a:repo.ssh_url)
    endif

    echo "fetching ".remote
    let result = system(fugitive#repo().git_command('fetch', remote))

    return remote

endfunction

function! vimhub#get_pr_files(id)

    let pr = b:prs[a:id]

    if s:git.has_commit(pr.head.sha) == 0
        call vimhub#fetch_repo(pr.head.repo)
    endif

    if s:git.has_commit(pr.base.sha) == 0
        call vimhub#fetch_repo(pr.base.repo)
    endif

    let cmd = fugitive#repo().git_command('diff', '--stat', '--name-only', pr.base.sha.'...'.pr.head.sha)
    let result = system(cmd)
    let pr_files = split(system(cmd), '\n')

    return pr_files

endfunction

function! vimhub#has_commit(commit)
    return s:git.has_commit(a:commit)
endfunction

exe "command! -buffer -nargs=0 Pulls :execute s:LoadInStatus(':execute vimhub#load_prs()', '__VimHub_Pulls__', 'pull_requests')"
