python3 << EOF
import vim
import fnmatch
import itertools
import os.path


def lambda_obj(*i, **d):
    cls = tuple(i)
    if len(cls) == 0: cls = (object,)
    return (type('', cls, d))()

def seq(*commands):
    return None


__callbacks__ = []
def add_callback(action):
    global __callbacks__
    __callbacks__.append(action)
    return len(__callbacks__) - 1

def call_callback(idx):
    global __callbacks__
    __callbacks__[idx]()

def call_callback_text(idx):
    return "call_callback(%d)" % idx
    

def map_normal_key(key, action):
    i = add_callback(action)
    vim.command("map <silent> <buffer> %s :python3 %s<cr>" % (key, call_callback_text(i)))

def map_insert_key(key, action):
    i = add_callback(action)
    vim.command("imap <silent> <buffer> %s <C-O>:python3 %s<cr>" % (key, call_callback_text(i)))

def add_event_listener(event, action):
    i = add_callback(action)
    vim.command("autocmd %s <buffer> python3 %s" % (event, call_callback_text(i)))

def new_panel():
    vim.command("botright new")
    vim.command("setlocal nobuflisted nomodified buftype=nofile bufhidden=wipe")


def start_insert_after_cursor():
    (line,col) = vim.current.window.cursor
    chars = len(vim.current.buffer[line - 1])
    if col == chars - 1:
        vim.command('startinsert!')
    else:
        vim.current.window.cursor = (line, col+1)
        vim.command('startinsert')


class SelectionList(object):
    def entries(self):
        return []
    def syntax(self):
        pass
    def no_match_entries(self, pattern):
        return []

class SelectionItem(object):
    dismiss = True
    def on_select(self):
        pass
    def match(self):
        return ''
    def view(self):
        return ''


class BufferList(SelectionList):
    def syntax(self):
        vim.command('syntax match Special |\[.\{-}\]|')
        vim.command('syntax match LineNr |[0-9]\+|')
        vim.command('syntax match Type |^.\{-} |')

    def entries(self):
        buffers = [ b for b in vim.buffers if b.options["buflisted"] ]

        # list the alt buf first
        alt = saved_state['alternate_buf_number']
        buffers = [ b for b in buffers if b.number == alt ] + [ b for b in buffers if b.number != alt ]

        def buf_name(b):
            name = vim.eval('bufname(%d)' % b.number)
            if b.options['buftype'] == b'':
                return os.path.basename(name)
            return name

        def tostr(x):
            return x if isinstance(x, str) else x.decode('utf-8')

        num_columns = 5
        columns = [ 
            [
                (lambda name: '(unnamed)' if name == '' else name) (buf_name(b)),
                '[+]' if b.options['modified'] else '[ ]',
                str(b.number),
                '[%s]' % tostr(b.options['filetype']),
                os.path.relpath(b.name) if b.name != '' else '',
            ] for b in buffers ]

        widths = [
            max( [ len(columns[j][i]) for j in range(len(columns)) ] )
            for i in range(num_columns)
        ]

        format_pattern = ' '.join([ '%-' + str(widths[i]) + 's' for i in range(num_columns)])

        class E(SelectionItem):
            def __init__(self,idx):
                self.i = idx
                self.name = buf_name(buffers[self.i])
            def match(self):
                return self.name
            def view(self): 
                return format_pattern % tuple(columns[self.i])
            def on_select(self):
                vim.current.buffer = buffers[self.i]

        return [ E(i) for i in range(len(buffers)) ]



class FileList(SelectionList):
    def __init__(self):
        self.history = []
        self.show_hidden = False

    def syntax(self):
        vim.command("syn match Type |^.*$|")
        vim.command("syn match Type |^.*\.|me=e-1")
        vim.command("syn match Normal |\..*$|")
        vim.command("syn match Directory |^.*/$|")
        vim.command("syn match Special |\[.*\]|")

    def entries(self):
        import os
        import os.path

        def partition(predicates, it):
            return tuple( (filter(p, it) for p in predicates ) )

        # hidden ==> show_hidden
        entries = [e for e in os.scandir('.') if not e.name.startswith('.') or self.show_hidden]

        part = partition( (lambda e: e.is_file(), lambda e: e.is_dir(), lambda e: not(e.is_file() or e.is_dir())), entries)
        sort_on_name = lambda e: e.name
        (files, dirs, others) = tuple(map(lambda entries: sorted(entries, key=sort_on_name), part))

        cwd = os.path.abspath(os.getcwd())

        def cd(d):
            if (len(self.history) > 0 and self.history[-1] == cwd) or os.path.abspath(os.path.expanduser(d)) == cwd:
                pass
            else:
                self.history.append(cwd)
            vim.command("cd " + d)

        file_list = (
            (lambda entry:
                lambda_obj(SelectionItem,
                    dismiss   = not(entry.is_dir()),
                    match     = lambda s: entry.name,
                    view      = lambda s: '  ' + (entry.name + '/' if entry.is_dir() else entry.name),
                    on_select = lambda s: cd(entry.name)
                                          if entry.is_dir()
                                          else vim.command("edit " + os.path.join(cwd, entry.name))
                )) (e)
            for e in itertools.chain(files, dirs, others)
        )

        up_dir = [
            lambda_obj(SelectionItem,
                dismiss = False,
                match = lambda s: '..',
                view = lambda s: '..',
                on_select = lambda s: cd('..')
            ),
            lambda_obj(SelectionItem,
                dismiss = False,
                match = lambda s: '',
                view = lambda s: cwd,
                on_select = lambda s: None
            ),
        ]

        def go_back():
            d = self.history.pop()
            vim.command("cd " + d)

        if len(self.history) > 0:
            up_dir.append(lambda_obj(SelectionItem,
                            dismiss = False,
                            match = lambda s: '',
                            view = lambda s: self.history[-1] + ' [go back]',
                            on_select = lambda s: go_back()
                        ))

        def flip_show_hidden():
            self.show_hidden = not self.show_hidden

        up_dir.append(lambda_obj(SelectionItem,
            dismiss = False,
            view = lambda s: '[hide hidden]' if self.show_hidden else '[show hidden]',
            on_select = lambda s: flip_show_hidden()
        ))

        user_home = os.path.expanduser('~')

        home_dir = [
            lambda_obj(SelectionItem,
                dismiss = False,
                view = lambda s: '  ~ %s [home]' % user_home,
                match = lambda s: '~ %s' % user_home,
                on_select = lambda s: cd('~')
            )
        ]

        return itertools.chain(up_dir, file_list, home_dir)

    def no_match_entries(self, pattern):
        cwd = os.path.abspath(os.getcwd())
        filepath = os.path.join(cwd, pattern)

        return [
            lambda_obj(SelectionItem,
                dismiss = True,
                view = lambda s: '[edit ' + filepath  + ']',
                on_select = lambda s: vim.command("edit " + filepath)
            ),
            lambda_obj(SelectionItem,
                dismiss = False,
                view = lambda s: '[mkdir ' + filepath  + ']',
                on_select = lambda s: seq(os.mkdir(filepath), vim.command("cd " + filepath))
            )
        ]


saved_state = {}

def selection_window(source):
    initial_window = vim.current.window
    initial_buffer = vim.current.buffer
    layout = []

    def dismiss():
        if (len(vim.windows) == 1):
            vim.current.buffer = initial_buffer
        else:
            if initial_window in vim.windows and initial_window.buffer == initial_buffer:
                vim.command("close")
                for w,wd,ht in layout:
                    w.width = wd
                    w.height = ht
                vim.current.window = initial_window
            else:
                # FIXME buffer might no longer exists. What to do in this case then depends on application.
                vim.current.buffer = initial_buffer

    saved_state['alternate_buf_number'] = int(vim.eval('bufnr("#")'))

    # save window layout
    layout = [ (w, w.width, w.height) for w in vim.windows]

    new_panel()
    vim.command('setlocal cursorline')
    vim.command('setlocal nowrap')
    vim.command('set filetype=Select')

    b = vim.current.buffer
    w = vim.current.window

    source.syntax()

    b[0] = ''

    def match_glob_pattern(pattern, string):
        return fnmatch.fnmatch(string.lower(), '*' + pattern.lower() + '*')

    matched = [None]
    def match(s):
        matches = [x for x in source.entries() if match_glob_pattern(s, x.match())]
        if matches == []:
            matches = source.no_match_entries(s)
        matched[0] = matches
        b[1:] = [ x.view() for x in matched[0] ]

    def text_changed():
        line = b[0].strip()
        match(line)
        if w.cursor[0] > 1: w.cursor = (1, len(b[0]))

    add_event_listener('TextChanged', text_changed)
    add_event_listener('TextChangedI', text_changed)

    def select():
        line = w.cursor[0]
        selected = (2 if line == 1 else line) - 2
        if len(matched[0]) > 0:
            entry = matched[0][selected]
            dis = entry.dismiss

            if dis: dismiss()

            entry.on_select()

            if not dis and b.number == vim.current.buffer.number:
                # action was token on the buffer, so redo the matches
                b[0] = ''
                text_changed()
            else:
                vim.command("stopinsert")
        else:
            print("Not matches found for the query")

    map_normal_key('<Enter>', select)
    map_insert_key('<Enter>', select)

    map_normal_key("q", dismiss)

    start_insert_after_cursor()
EOF


function! Buffers()
python3 selection_window(BufferList())
endfunction

function! Files()
python3 selection_window(FileList())
endfunction

