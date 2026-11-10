"""Recover original Lua daytime functions and their config-backed arithmetic.

Only the observed PE wrapper/x87 instruction forms are accepted. Byte addresses,
routine bytes, config initializers and source hashes remain reviewable evidence.
"""
import hashlib
import math
import struct

from tools.native_config import recover

LENGTHS = ['DawnToDayLength', 'DayTimeLength', 'DayToDuskLength', 'DuskTimeLength',
           'DuskToNightLength', 'NightTimeLength', 'NightToDawnLength', 'DawnTimeLength']


def extract(raw, overrides):
    pe = struct.unpack_from('<I', raw, 0x3c)[0]
    if raw[pe:pe+4] != b'PE\0\0': raise ValueError('Not the supplied PE executable')
    optional = pe+24
    base = struct.unpack_from('<I',raw,optional+28)[0]
    count = struct.unpack_from('<H',raw,pe+6)[0]
    size = struct.unpack_from('<H',raw,pe+20)[0]
    sections = []
    for i in range(count):
        entry = optional+size+i*40
        _, virtual, length, offset = struct.unpack_from('<IIII',raw,entry+8)
        sections.append((base+virtual,offset,length))

    def offset(address):
        return next(start+address-virtual for virtual,start,length in sections if virtual<=address<virtual+length)

    def address(offset):
        return next(virtual+offset-start for virtual,start,length in sections if start<=offset<start+length)

    native = recover(raw,['day','dusk','dawn','night'])
    names = {int(native[key]['data'],16):key for key in LENGTHS}
    configuration = {key:float(overrides.get(key,native[key]['value'])) for key in LENGTHS+['TimeOfDaySpeed']}
    if any(not math.isfinite(value) or value<0 for value in configuration.values()) or sum(configuration[key] for key in LENGTHS)<=0:
        raise ValueError('Invalid original day-cycle configuration')
    functions = {}
    for name in ['Midday','Sunset','Midnight']:
        text_offset = raw.index(name.encode()+b'\0')
        reference = struct.pack('<I',address(text_offset))
        candidates = []
        cursor = 0
        while True:
            cursor=raw.find(reference,cursor)
            if cursor<0: break
            wrapper=struct.unpack_from('<I',raw,cursor+4)[0]
            try: start=offset(wrapper)
            except StopIteration: cursor+=1; continue
            if raw[start:start+1]==b'\xe8': candidates.append((cursor,wrapper,start))
            cursor+=1
        if len(candidates)!=1: raise ValueError('Ambiguous daytime Lua registration: '+name)
        registration,wrapper,start=candidates[0]
        function=wrapper+5+struct.unpack_from('<i',raw,start+1)[0]
        begin=offset(function)
        cursor=begin
        if raw[cursor:cursor+4]!=bytes.fromhex('55 8b ec 51'): raise ValueError('Unknown daytime prologue')
        cursor+=4
        if raw[cursor:cursor+2]!=b'\xd9\x05': raise ValueError('Unknown daytime initial load')
        stack=[[[names[struct.unpack_from('<I',raw,cursor+2)[0]],1.0]]]
        cursor+=6
        while raw[cursor:cursor+2] in [b'\xdc\x0d',b'\xd8\x05',b'\xd9\x05',b'\xde\xc1']:
            opcode=raw[cursor:cursor+2]
            if opcode==b'\xde\xc1':
                right=stack.pop()
                stack[-1].extend(right)
                cursor+=2
                continue
            pointer=struct.unpack_from('<I',raw,cursor+2)[0]
            if opcode==b'\xdc\x0d':
                for term in stack[-1]: term[1]*=struct.unpack_from('<d',raw,offset(pointer))[0]
            elif opcode==b'\xd9\x05': stack.append([[names[pointer],1.0]])
            else: stack[-1].append([names[pointer],1.0])
            cursor+=6
        ending=bytes.fromhex('d9 5d fc d9 45 fc 8b e5 5d c3')
        if raw[cursor:cursor+len(ending)]!=ending: raise ValueError('Unknown daytime return')
        if len(stack)!=1: raise ValueError('Unknown daytime expression stack')
        terms=stack[0]
        cursor+=len(ending)
        functions[name]={'terms':terms,'value':sum(configuration[key]*weight for key,weight in terms),
                         'registration':hex(address(registration)),'wrapper':hex(wrapper),
                         'routine':hex(function),'bytes':raw[begin:cursor].hex()}
    return {'executable_sha256':hashlib.sha256(raw).hexdigest(), 'configuration':configuration,
            'native_configuration':{key:native[key] for key in LENGTHS+['TimeOfDaySpeed']},
            'functions':functions,'period':sum(configuration[key] for key in LENGTHS)}
