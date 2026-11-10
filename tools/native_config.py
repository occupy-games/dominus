"""Read original PE float-config initializers, retaining byte-address evidence."""
import re
import struct


def recover(raw, keywords=None):
    pe = struct.unpack_from('<I', raw, 0x3c)[0]
    if raw[pe:pe+4] != b'PE\0\0': raise ValueError('Not the supplied PE executable')
    optional = pe+24
    base = struct.unpack_from('<I',raw,optional+28)[0]
    count = struct.unpack_from('<H',raw,pe+6)[0]
    size = struct.unpack_from('<H',raw,pe+20)[0]
    sections = []
    for index in range(count):
        offset = optional+size+index*40
        _, virtual, length, start = struct.unpack_from('<IIII',raw,offset+8)
        sections.append((base+virtual,start,length))
    def virtual(offset):
        return next(address+offset-start for address,start,length in sections if start<=offset<start+length)
    def offset(address):
        return next(start+address-virtual for virtual,start,length in sections if virtual<=address<virtual+length)
    text = next((start,length) for address,start,length in sections if address==base+0x1000)
    result = {}
    for match in re.finditer(rb'[A-Za-z][A-Za-z0-9_]{3,90}\x00', raw):
        name = match[0][:-1].decode()
        selected = keywords if keywords is not None else ['mission','expedition','champion','meteor','swamp','blight','shrine','follower','beautif','stamina','sticker','reward','pack']
        if not any(word in name.lower() for word in selected): continue
        string_address = virtual(match.start())
        reference = raw.find(b'\x68'+struct.pack('<I',string_address),text[0],sum(text))
        if reference<0: continue
        load = raw.rfind(b'\xd9\x05',max(text[0],reference-100),reference)
        if load<0: continue
        pointer = struct.unpack_from('<I',raw,load+2)[0]
        # Float initialization must immediately store to a config value slot.
        if raw[load+6:load+8] != b'\xd9\x15': continue
        try: value = struct.unpack_from('<f',raw,offset(pointer))[0]
        except (StopIteration,struct.error): continue
        if not (-1e20 < value < 1e20): continue
        result[name] = {'value':value,'initializer':hex(virtual(load)),'data':hex(pointer),'name':hex(string_address),'slot':hex(struct.unpack_from('<I',raw,load+8)[0])}
    return result
