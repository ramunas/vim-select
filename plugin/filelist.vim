vim9script

def Init()
    syntax match Type |^.*$|
    syntax match Type |^.*\.|me=e-1
    syntax match Normal |\..*$|
    syntax match Directory |^.*/$|
    syntax match Directory |\[.*\]|
    # syntax match Special |\[.*\]|
    b:last_dir = getcwd()
enddef

def Partition(list: list<any>, Pred: func(any): bool): list<list<any>>
    var a = []
    var b = []
    for x in list
        if Pred(x)
            add(a, x)
        else
            add(b, x)
        endif
    endfor
    return [a, b]
enddef

def GlobPat(pat: string): string
    var pattern = substitute(pat, '\~', $HOME, 'g')
    if pattern == ''
        return '*'
    endif

    if pattern[ : 1] == "#/"
        var top = system("git rev-parse --show-toplevel")
        if v:shell_error != 0
            top = ""
        endif
        top = substitute(top, "\n", "", '')
        pattern = top .. "/" .. pattern[2 : ] .. '*'
    elseif pattern[ : 2] == "../" || pattern[ : 1] == "./" || pattern[ : 0] == "/"
        pattern = pattern .. '*'
    else
        pattern = '*' .. pattern .. '*'
    endif

    pattern = substitute(pattern, '\*\+', '*', 'g')
    return pattern
enddef

def List(pattern: string): list<dict<any>>
    var glob_pattern = GlobPat(pattern)
    var re_pattern = glob2regpat(glob_pattern)
    var all_files = glob(glob_pattern, true, true, true)

    var [directories, files] = Partition(all_files, (f) => isdirectory(f))

    sort(files)
    sort(directories)

    var result = []
    var KeepOpen = () => {
        execute ':' w:selection_window 'wincmd w'
        b:selection_keep_open = true
    }

    extend(result, mapnew(files, (_, x): dict<any> => (
        {
                view: () =>
                    '  ' .. x,
                select: (() => {
                    execute 'edit' escape(x, ' %')
                })
        })))

    extend(result, mapnew(directories, (_, x): dict<any> => (
        {
                view: () =>
                    '  ' .. x .. '/',
                select: (() => {
                    KeepOpen()
                    b:last_dir = getcwd()
                    execute 'cd' escape(x, ' %')
                })
        })))

    var special = [
        {
                name: '..',
                view: () => ' ..',
                select: () => {
                    KeepOpen()
                    b:last_dir = getcwd()
                    cd ..
                }
        },
        {
                name: '-',
                view: () => ' - ' .. b:last_dir,
                select: () => {
                    KeepOpen()
                    var dir = b:last_dir
                    b:last_dir = getcwd()
                    execute 'cd' dir
                }
        },
        {
                name: './',
                view: () => ' . ' .. getcwd(),
                select: () => {
                    KeepOpen()
                }
        }
        ]

    filter(special, (_, x) => x['name'] =~ re_pattern)
    extend(result, special)

    if len(result) == 0
        extend(result, [
            {
                    view: () => '  edit ' .. pattern,
                    select: () => {
                        execute 'edit' escape(pattern, ' %')
                    }
            },
            {
                    view: () => '  mkdir ' .. pattern,
                    select: () => {
                        KeepOpen()
                        system('mkdir ' .. shellescape(pattern))
                        execute 'cd' escape(pattern, ' %')
                    }
            }
            ])
    endif

    return result
enddef

import "./select2.vim" as sel
command! ShowFileSelection sel.ShowSelectionWindow(List, Init)
