"""Compile supplied voyage Lua to inert, serializable instructions.

This is a parser, not eval/exec. Runtime builtins are explicitly implemented by
the pure simulation adapter. Unknown syntax fails extraction rather than being
silently removed. Numeric formal parameters in two supplied tutorial hooks are
retained as inert parameter names (a source typo affecting tooltip hooks only).
"""
import re


class CompileError(ValueError):
    pass


TOKEN = re.compile(r'''\s+|--\[(=*)\[.*?\]\1\]|--[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?|[A-Za-z_]\w*|\.\.|~=|==|<=|>=|[^\s]''', re.S)
PRECEDENCE = {'or': 1, 'and': 2, '<': 3, '>': 3, '<=': 3, '>=': 3, '~=': 3, '==': 3,
              '..': 4, '+': 5, '-': 5, '*': 6, '/': 6, '%': 6, '^': 8}


class Compiler:
    def __init__(self, source):
        self.tokens = [m.group() for m in TOKEN.finditer(source) if not m.group().isspace() and not m.group().startswith('--')]
        self.tokens.append('<eof>')
        self.cursor = 0
        self.functions = {}
        self.calls = set()
        self.quirks = []

    def peek(self):
        return self.tokens[self.cursor]

    def take(self, expected=None):
        token = self.peek()
        if expected is not None and token != expected:
            raise CompileError(f'Expected {expected!r}, got {token!r} near {self.tokens[max(0,self.cursor-5):self.cursor+8]}')
        self.cursor += 1
        return token

    def accept(self, token):
        if self.peek() == token:
            self.take()
            return True
        return False

    def function(self):
        self.take('(')
        parameters = []
        while self.peek() != ')':
            parameter = self.take()
            if parameter.isdigit():
                self.quirks.append('numeric formal parameter ' + parameter)
            parameters.append(parameter)
            if not self.accept(','): break
        self.take(')')
        body = self.block({'end'})
        self.take('end')
        key = str(len(self.functions))
        self.functions[key] = {'params': parameters, 'body': body}
        return ['function', key]

    def block(self, end):
        statements = []
        while self.peek() not in end and self.peek() != '<eof>':
            if self.accept(';'): continue
            if self.peek() == 'end' and end == {'<eof>'}:
                self.take()
                self.quirks.append('orphan end after commented-out tooltip hook')
                continue
            local = self.accept('local')
            if self.accept('function'):
                name = self.take()
                statements.append(['local' if local else 'assign', ['var', name], self.function()])
            elif self.accept('if'):
                branches = []
                condition = self.expression()
                self.take('then')
                branches.append([condition, self.block({'elseif', 'else', 'end'})])
                while self.accept('elseif'):
                    condition = self.expression()
                    self.take('then')
                    branches.append([condition, self.block({'elseif', 'else', 'end'})])
                other = self.block({'end'}) if self.accept('else') else []
                self.take('end')
                statements.append(['if', branches, other])
            elif self.accept('return'):
                value = ['literal', None] if self.peek() in end or self.peek() == ';' else self.expression()
                statements.append(['return', value])
            elif self.accept('break'):
                statements.append(['break'])
            elif self.accept('for'):
                name = self.take()
                self.take('=')
                start = self.expression()
                self.take(',')
                stop = self.expression()
                step = self.expression() if self.accept(',') else ['literal', 1]
                self.take('do')
                body = self.block({'end'})
                self.take('end')
                statements.append(['for', name, start, stop, step, body])
            else:
                target = self.expression()
                if self.accept(','):
                    targets = [target, self.expression()]
                    while self.accept(','): targets.append(self.expression())
                    self.take('=')
                    statements.append(['local_many' if local else 'assign_many',targets,self.expression()])
                elif self.accept('='):
                    statements.append(['local' if local else 'assign', target, self.expression()])
                elif local:
                    statements.append(['local', target, ['literal', None]])
                elif target[0] in ['call', 'method_call']: statements.append(['expr', target])
                else: raise CompileError(f'Expected assignment or call, got {target} near {self.tokens[self.cursor:self.cursor+5]}')
        return statements

    def expression(self, minimum=0):
        token = self.take()
        if token in ['not', '-', '#']:
            left = ['unary', token, self.expression(7)]
        elif token == 'function': left = self.function()
        elif token == '(':
            left = self.expression()
            self.take(')')
        elif token == '{':
            entries = []
            index = 1
            while self.peek() != '}':
                if self.accept('['):
                    key = self.expression()
                    self.take(']')
                    self.take('=')
                    value = self.expression()
                elif self.cursor+1 < len(self.tokens) and self.tokens[self.cursor+1] == '=':
                    key = ['literal', self.take()]
                    self.take('=')
                    value = self.expression()
                else:
                    key = ['literal', index]
                    index += 1
                    value = self.expression()
                entries.append([key,value])
                if not (self.accept(',') or self.accept(';')): break
            self.take('}')
            left = ['table', entries]
        elif token[0] in ['"', "'"]:
            value = re.sub(r'\\(.)', lambda m: {'n':'\n','r':'\r','t':'\t'}.get(m[1],m[1]), token[1:-1])
            left = ['literal', value]
        elif re.fullmatch(r'(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?',token):
            left = ['literal', float(token) if any(c in token for c in '.eE') else int(token)]
        elif token in ['true','false','nil']: left = ['literal', {'true':True,'false':False,'nil':None}[token]]
        elif re.fullmatch(r'[A-Za-z_]\w*',token): left = ['var',token]
        else: raise CompileError(f'Invalid expression token {token!r}')
        while True:
            if self.accept('.'):
                left = ['index',left,['literal',self.take()]]
            elif self.accept('['):
                left = ['index',left,self.expression()]
                self.take(']')
            elif self.accept(':'):
                method = self.take()
                self.take('(')
                arguments = []
                while self.peek() != ')':
                    arguments.append(self.expression())
                    if not self.accept(','): break
                self.take(')')
                left = ['method_call',left,method,arguments]
            elif self.accept('('):
                arguments = []
                while self.peek() != ')':
                    arguments.append(self.expression())
                    if not self.accept(','): break
                self.take(')')
                if left[0] == 'var': self.calls.add(left[1])
                left = ['call',left,arguments]
            elif self.peek() in PRECEDENCE and PRECEDENCE[self.peek()] >= minimum:
                op = self.take()
                right = self.expression(PRECEDENCE[op] + (0 if op in ['^','..'] else 1))
                left = ['binary',op,left,right]
            else: break
        return left

    def compile(self):
        body = self.block({'<eof>'})
        self.take('<eof>')
        return {'body':body,'functions':self.functions,'calls':sorted(self.calls),'source_quirks':self.quirks}


def compile_script(source):
    return Compiler(source).compile()
