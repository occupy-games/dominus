"""Recover native house inheritance fields and resolve the supplied unit rows.

The PE's actual registration slots and multiplication instructions determine
which fields inherit and whether their arithmetic is integer or float32.
Unsupported numeric source text stays unresolved; it is never guessed.
"""
import hashlib
import json
from pathlib import Path
import re
import struct

from tools.current_cards import decode_archive, rows

ROOT = Path(__file__).resolve().parents[1]


def native_fields(raw):
    pe=struct.unpack_from('<I',raw,60)[0]
    if raw[pe:pe+4]!=b'PE\0\0': raise ValueError('Not the supplied PE executable')
    optional=pe+24
    base=struct.unpack_from('<I',raw,optional+28)[0]
    sections=[]
    count=struct.unpack_from('<H',raw,pe+6)[0]
    size=struct.unpack_from('<H',raw,pe+20)[0]
    for i in range(count):
        entry=optional+size+i*40
        _,virtual,length,start=struct.unpack_from('<IIII',raw,entry+8)
        sections.append((base+virtual,start,length))

    def offset(address): return next(start+address-virtual for virtual,start,length in sections if virtual<=address<virtual+length)
    def address(offset): return next(virtual+offset-start for virtual,start,length in sections if start<=offset<start+length)
    registrations={}
    start,end=offset(0x10030ed4),offset(0x10031448)
    for match in re.finditer(rb'\x68(.{4})\x68(.{4})\x56\xe8(.{4})',raw[start:end],re.S):
        slot,name,relative=struct.unpack('<IIi',b''.join(match.groups()))
        call=start+match.start()+11
        if address(call)+5+relative!=0x10170c10: raise ValueError('Unknown house column registration')
        position=offset(name)
        label=raw[position:raw.index(0,position)].decode('ascii').strip()
        registrations[label.casefold()]={'name':label,'slot':hex(slot),'registration':hex(address(start+match.start()))}
    if registrations.get('parent',{}).get('slot')!='0x10fc7048': raise ValueError('Unknown house parent field')
    raw_base=0x10fc701c
    by_offset={int(value['slot'],16)-raw_base:value for value in registrations.values()}
    start,end=offset(0x1002bfd0),offset(0x1002c292)
    cursor=start
    fields={}

    def memory(opcode,short,large,zero=None):
        nonlocal cursor
        if raw[cursor]!=opcode: raise ValueError('Unknown native house arithmetic opcode')
        mode=raw[cursor+1]
        cursor+=2
        if zero is not None and mode==zero: return 0
        if mode==short:
            displacement=struct.unpack_from('<b',raw,cursor)[0]; cursor+=1
        elif mode==large:
            displacement=struct.unpack_from('<i',raw,cursor)[0]; cursor+=4
        else: raise ValueError('Unknown native house arithmetic operand')
        return displacement

    while cursor<end:
        begin=cursor
        if raw[cursor]==0xd9:
            parent=memory(0xd9,0x40,0x80)
            child=memory(0xd8,0x4e,0x8e,0x0e)+0x40
            stored=memory(0xd9,0x5e,0x9e,0x1e)+0x40
            kind='float32'
        elif raw[cursor]==0x8b:
            mode=raw[cursor+1]
            edx=mode in [0x50,0x90]
            parent=memory(0x8b,0x50 if edx else 0x48,0x90 if edx else 0x88)
            if raw[cursor:cursor+3]!=(b'\x0f\xaf\x56' if edx else b'\x0f\xaf\x4e'): raise ValueError('Unknown house integer multiplication')
            child=struct.unpack_from('<b',raw,cursor+3)[0]+0x40
            cursor+=4
            stored=memory(0x89,0x56 if edx else 0x4e,0x96 if edx else 0x8e)+0x40
            kind='int32'
        else: raise ValueError('Unknown native house inheritance instruction')
        if parent!=child or parent!=stored or parent not in by_offset: raise ValueError('Mismatched house inheritance field')
        field=by_offset[parent]
        fields[field['name'].casefold()]=dict(field,offset=parent,arithmetic=kind,address=hex(address(begin)),bytes=raw[begin:cursor].hex())
    if cursor!=end or 'base size' not in fields or 'build time' not in fields: raise ValueError('Incomplete house inheritance routine')
    return {'executable_sha256':hashlib.sha256(raw).hexdigest(),'routine':'0x1002bfd0','bytes':raw[start:end].hex(),
            'raw_row_base':hex(raw_base),'row_bytes':0x130,'fields':fields}


def resolve(table,evidence):
    headers=[label.strip() for label in table[0]]
    indices={label.casefold():i for i,label in enumerate(headers)}
    records={}
    for row in table[1:]:
        if len(row)<len(headers) or not row[0].lstrip('-').isdigit(): continue
        name=row[indices['name hash']]
        parent=row[indices['parent']]
        if parent and parent not in records: raise ValueError('House parent is not defined before its child: '+name)
        values={}
        unsupported={}
        for key,field in evidence['fields'].items():
            if key not in indices:
                unsupported[key]='native column absent from current source table'
                continue
            value=row[indices[key]].strip()
            try: value=float(value or '0')
            except ValueError:
                unsupported[key]=row[indices[key]]
                continue
            if field['arithmetic']=='float32': value=struct.unpack('<f',struct.pack('<f',value))[0]
            else: value=int(value)
            if parent:
                if key not in records[parent]['values']:
                    unsupported[key]='unresolved parent '+parent
                    continue
                value*=records[parent]['values'][key]
                if field['arithmetic']=='float32': value=struct.unpack('<f',struct.pack('<f',value))[0]
            values[key]=value
        records[name]={'parent':parent,'raw':dict(zip(headers,row)), 'values':values,'unresolved':unsupported}
    return records


def extract(source=ROOT/'data/godus2_4',output=ROOT/'game/assets/original/campaign'):
    executable=(source/'godus.s86').read_bytes()
    archive=(source/'received/godussteamrel/balance.datz').read_bytes()
    files=decode_archive(archive)
    table_name='balance/housevalues.csv'
    evidence=native_fields(executable)
    records=resolve(rows(files,table_name),evidence)
    result={'source':'received/godussteamrel/balance.datz','source_sha256':hashlib.sha256(archive).hexdigest(),
            'table':table_name,'table_sha256':hashlib.sha256(files[table_name]).hexdigest(),
            'native':evidence,'records':records}
    output.mkdir(parents=True,exist_ok=True)
    (output/'house-rules.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    return result


if __name__=='__main__':
    data=extract()
    print(f"Original house inheritance: {len(data['records'])} records, {len(data['native']['fields'])} multiplied fields")
