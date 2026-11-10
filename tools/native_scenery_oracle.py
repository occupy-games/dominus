"""Bounded x86 comparison of supplied the original source scenery routines.

This is an offline research oracle, never a game dependency. CPU instructions
run in Unicorn with in-memory terrain/table adapters; no original executable
entry point, OS imports, renderer, audio or network is started.
Install the optional emulator in an isolated tool directory, then use
PYTHONPATH=build/research-tools python3 -m tools.native_scenery_oracle.
"""
import argparse
from collections import deque
import hashlib
import json
from pathlib import Path
import struct

from tools.current_cards import decode_archive, rows

ROOT = Path(__file__).resolve().parents[1]


class NativeImage:
    def __init__(self, raw):
        self.raw = raw
        pe = struct.unpack_from('<I', raw, 60)[0]
        if raw[pe:pe+4] != b'PE\0\0': raise ValueError('Not the supplied PE executable')
        optional = pe+24
        self.base = struct.unpack_from('<I', raw, optional+28)[0]
        self.size = struct.unpack_from('<I', raw, optional+56)[0]
        self.sections = []
        for i in range(struct.unpack_from('<H', raw, pe+6)[0]):
            entry = optional+struct.unpack_from('<H', raw, pe+20)[0]+i*40
            virtual_size, virtual, length, start = struct.unpack_from('<IIII', raw, entry+8)
            self.sections.append((self.base+virtual, start, length, virtual_size))

    def read(self, address, length):
        offset = next(start+address-virtual for virtual,start,size,_ in self.sections if virtual <= address < virtual+size)
        return self.raw[offset:offset+length]


class Oracle:
    STACK = 0x20000000
    SCRATCH = 0x21000000
    POOL = 0x30000000
    GRIDS = 0x34000000

    def __init__(self, raw):
        from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
        from unicorn import x86_const
        self.regs = x86_const
        self.cpu = Uc(UC_ARCH_X86, UC_MODE_32)
        self.hook_kind = UC_HOOK_CODE
        self.handles = []
        self.image = NativeImage(raw)
        self.cpu.mem_map(self.image.base, (self.image.size+4095)&~4095)
        for address,start,length,_ in self.image.sections:
            self.cpu.mem_write(address,raw[start:start+length])
        self.cpu.mem_map(0,4096)  # The function's local SEH chain, not a host TLS.
        self.cpu.mem_map(self.STACK,0x100000)
        self.cpu.mem_map(self.SCRATCH,0x10000)
        self.cpu.mem_map(self.POOL,0x2000000)
        self.cpu.mem_map(self.GRIDS,0x400000)
        self.cpu.mem_write(self.SCRATCH+0x800,b'\xd9\x05'+struct.pack('<I',self.SCRATCH+0x900)+b'\xc3')
        self.records = []
        self.grids = {}
        self.adapters = {}
        self.touched = set()
        self.error = ''
        self.trace = deque(maxlen=20)
        self.source = ''
        self.authored = False
        self.table = []
        self.terrain = b''
        self.fields = []
        self.configuration = {}
        self.skip_zero = False

    def integer(self,address): return struct.unpack('<I',self.cpu.mem_read(address,4))[0]
    def float(self,address): return struct.unpack('<f',self.cpu.mem_read(address,4))[0]
    def set_integer(self,address,value): self.cpu.mem_write(address,struct.pack('<I',value&0xffffffff))
    def set_float(self,address,value): self.cpu.mem_write(address,struct.pack('<f',value))

    def arguments(self,count):
        stack = self.cpu.reg_read(self.regs.UC_X86_REG_ESP)
        return struct.unpack('<'+'I'*count,self.cpu.mem_read(stack+4,count*4))

    def return_integer(self,value=0,pop=0):
        stack = self.cpu.reg_read(self.regs.UC_X86_REG_ESP)
        self.cpu.reg_write(self.regs.UC_X86_REG_EAX,value&0xffffffff)
        self.cpu.reg_write(self.regs.UC_X86_REG_ESP,stack+4+pop)
        self.cpu.reg_write(self.regs.UC_X86_REG_EIP,self.integer(stack))

    def return_float(self,value):
        self.set_float(self.SCRATCH+0x900,value)
        self.cpu.reg_write(self.regs.UC_X86_REG_EIP,self.SCRATCH+0x800)

    def hook(self,cpu,address,size,user):
        self.trace.append(address)
        if address in self.adapters:
            self.touched.add(address)
            self.adapters[address]()
        elif not (self.image.base+0x1000 <= address < self.image.base+0x497800 or self.SCRATCH <= address < self.SCRATCH+0x1000):
            self.error='Unadapted native service at '+hex(address)+' after '+','.join(hex(v) for v in self.trace)
            cpu.emu_stop()

    def call(self,address,args=(),floating=False,limit=20000000):
        self.cpu.reg_write(self.regs.UC_X86_REG_ESP,self.STACK+0x80000)
        code = bytearray(b'\xdb\xe3')  # FNINIT: explicit fresh x87 state.
        for value in reversed(args): code.extend(b'\x68'+struct.pack('<I',value&0xffffffff))
        call = self.SCRATCH+len(code)
        code.extend(b'\xe8'+struct.pack('<i',address-call-5))
        code.extend(b'\x81\xc4'+struct.pack('<I',len(args)*4))
        if floating: code.extend(b'\xd9\x1d'+struct.pack('<I',self.SCRATCH+0x904))
        self.cpu.mem_write(self.SCRATCH,bytes(code))
        # Unicorn caches translated immediates across emu_start calls. The call
        # harness changes its argument bytes, so invalidate only that harness.
        self.cpu.ctl_remove_cache(self.SCRATCH,self.SCRATCH+0x400)
        self.error=''
        self.cpu.emu_start(self.SCRATCH,self.SCRATCH+len(code),count=limit)
        if self.error: raise ValueError(self.error)
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=self.SCRATCH+len(code):
            raise ValueError('Native instruction budget exhausted at '+hex(self.cpu.reg_read(self.regs.UC_X86_REG_EIP)))
        return self.float(self.SCRATCH+0x904) if floating else self.cpu.reg_read(self.regs.UC_X86_REG_EAX)

    def coordinate_hash(self,x,z,salt,minimum,maximum,floating=False):
        self.cpu.mem_write(self.SCRATCH+0x1000,struct.pack('<ff',x,z))
        if floating:
            bounds=struct.unpack('<II',struct.pack('<ff',minimum,maximum))
        else: bounds=(minimum,maximum)
        return self.call(0x102765f0 if floating else 0x10276500,[self.SCRATCH+0x1000,salt,*bounds],floating)

    def configure(self,terrain,tree,rock,values,configuration=None):
        self.terrain=terrain
        self.fields=[tree,rock]
        self.table=values
        self.configuration=dict(configuration or {})
        for name,pointer in [('loc2Start',0x105b2d08),('loc3Start',0x105b2d0c),('TreeTypeOverride',0x105d9290)]:
            if name in self.configuration: self.set_float(pointer,float(self.configuration[name]))
        for row in values[1:]:
            if not row or not row[0].isdigit(): continue
            kind=int(row[0])
            self.set_integer(0x10fcbc38+kind*32,int(row[1]))
            self.set_integer(0x10fcbc3c+kind*32,int(row[2]))
        self.set_integer(0x10f2e7fc,self.POOL)
        # Original identity matrix used by the placement constructor. Scenery
        # transform output below is captured before renderer/event registration.
        for i in range(12): self.set_float(0x11165d1c+i*4,1. if i in [0,4,8] else 0.)
        self.set_integer(0x10c98448,0)  # Homeworld source info.csv: Colours,0.
        self.adapters={
            0x10144780:lambda:self.return_integer(), # terrain read lock
            0x10144790:lambda:self.return_integer(), # matching unlock
            0x10144820:self.loaded,
            0x101453c0:self.density,
            0x101450b0:self.height,
            0x100854b0:self.allocate,
            0x10094820:self.occupy,
            0x100e5eb0:lambda:self.return_integer(pop=16), # dirty-region notification
            0x10157050:self.capture,
            0x1015aed0:lambda:self.return_integer(), # renderer/event registration
            0x10179af0:lambda:self.return_integer(), # diagnostic logging
            0x1035f830:lambda:self.return_integer(), # local stack-cookie check
        }
        for handle in self.handles: self.cpu.hook_del(handle)
        self.handles = [self.cpu.hook_add(self.hook_kind,self.hook,begin=address,end=address)
                        for address in self.adapters]

    def load_authored(self,table):
        # All remaining cells in this scope's authored CSV are blank/default.
        # Populate the actual native table and execute the original loop, which
        # truncates its float coordinates before calling the object constructor.
        from tools.campaign import stream_hash
        for index,row in enumerate(table[1:]):
            if not row or not row[0]: continue
            if row[0] not in ['rock1']+['godseed'+str(i) for i in range(1,6)] or any(row[4:]):
                raise ValueError('Unsupported authored scenery row')
            if index>=110: raise ValueError('Original authored table budget exceeded')
            pointer=0x10f18f64+index*36
            self.set_integer(pointer,stream_hash(row[0]))
            self.set_float(pointer+4,float(row[1]))
            self.set_float(pointer+8,float(row[2]))
            self.set_float(pointer+12,float(row[3] or 0))
        self.authored=True
        self.call(0x1025f770)
        self.authored=False

    def loaded(self):
        x,z=self.arguments(2)
        loaded=0<=x<1024 and 0<=z<1024
        # The two zero densities cannot pass either exclusive hash comparison.
        # Both hashes are coordinate functions with no RNG/global mutation.
        # This optional fast-forward has a separate full-load comparison.
        if loaded and self.skip_zero and not self.authored:
            loaded=bool(self.fields[0][z*1024+x] or self.fields[1][z*1024+x])
        self.return_integer(int(loaded))

    def density(self):
        kind,x,z=self.arguments(3)
        if kind not in [0,1]: raise ValueError('Unknown source density field')
        self.return_integer(self.fields[kind][z*1024+x] if x<1024 and z<1024 else 0)

    def height(self):
        x,z=self.arguments(2)
        self.return_float(self.terrain[z*1024+x] if x<1024 and z<1024 else 0)

    def allocate(self):
        if self.cpu.reg_read(self.regs.UC_X86_REG_ECX)!=0x10f2e7fc: raise ValueError('Unknown original object pool')
        pointer=self.POOL+len(self.records)*0xec
        if pointer+0xec>self.POOL+0x2000000: raise ValueError('Scenery pool budget exhausted')
        self.records.append({'pointer':pointer,'authored':self.authored,'cells':[]})
        self.return_integer(pointer)

    def occupy(self):
        if self.cpu.reg_read(self.regs.UC_X86_REG_ECX)!=0x10f2d7fc: raise ValueError('Unknown original occupancy map')
        index,object_id=self.arguments(2)
        if index not in self.records[object_id]['cells']: self.records[object_id]['cells'].append(index)
        x,z=index%1024,index//1024
        tile=(z//32)*32+x//32
        if tile not in self.grids:
            pointer=self.GRIDS+len(self.grids)*2048
            self.grids[tile]=pointer
            self.cpu.mem_write(pointer,b'\xff'*2048)
            self.set_integer(0x10f2d7fc+tile*4,pointer)
        pointer=self.grids[tile]
        self.cpu.mem_write(pointer+((z%32)*32+x%32)*2,struct.pack('<H',object_id))
        self.return_integer(pop=8)

    def capture(self):
        pointer=self.cpu.reg_read(self.regs.UC_X86_REG_ECX)
        record=self.records[(pointer-self.POOL)//0xec]
        record.update(type=self.integer(pointer+0x34),root_x=self.integer(pointer+0x38),root_z=self.integer(pointer+0x3c),
                      x=self.float(pointer+0x28),z=self.float(pointer+0x2c),height=self.float(pointer+0x30),rotation=self.float(pointer+0x48))
        self.return_integer()

    def generate(self,bounds):
        self.call(0x1025fcd0,bounds,limit=max(20000000,(bounds[2]-bounds[0])*(bounds[3]-bounds[1])*3000))
        return [{k:v for k,v in item.items() if k!='pointer'} for item in self.records]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bounds',type=int,nargs=4,default=[150,115,175,140])
    parser.add_argument('--output',type=Path,default=ROOT/'build/native-scenery-oracle.json')
    parser.add_argument('--skip-zero-density',action='store_true')
    args=parser.parse_args()
    source=ROOT/'data/godus2_4'
    raw=(source/'godus.s86').read_bytes()
    files=decode_archive((source/'received/godussteamrel/balance.datz').read_bytes())
    values=rows(files,'assets/map_object_values.csv')
    configuration={row[0]:row[1] for path in ['config.csv','balance/config.csv'] for row in rows(files,path) if len(row)>1}
    fields=[(ROOT/'game/assets/original/campaign'/('homeworld6-'+name+'.bin')).read_bytes() for name in ['terrain','tree','rock']]
    oracle=Oracle(raw)
    oracle.configure(*fields,values,configuration)
    oracle.skip_zero=args.skip_zero_density
    oracle.load_authored(rows(files,'initialworldsetup6/initialmapobjects.csv'))
    records=oracle.generate(args.bounds)
    result={'executable_sha256':hashlib.sha256(raw).hexdigest(),'routine':'0x1025fcd0','bounds':args.bounds,
            'adapters':[hex(v) for v in sorted(oracle.touched)],'skip_zero_density':args.skip_zero_density,
            'configuration':{key:configuration[key] for key in ['loc2Start','loc3Start']},
            'records':records}
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print('Native scenery:',len(records),'objects;',sum(item['type']>=20 for item in records),'rocks')


if __name__=='__main__': main()
