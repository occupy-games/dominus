"""Bounded original building/base-entity initialization observations.

Executes the complete house initializer and base entity initializer with explicit
resolved-stat, model-resource, clock, terrain, scenery and spatial adapters. This
is a constructor-state comparison, not a complete building lifetime or campaign.
"""
import argparse
import hashlib
import json
import struct

from tools.house_selection import extract
from tools.native_house_selection_oracle import SelectionOracle
from tools.native_scenery_oracle import ROOT


class ConstructorOracle(SelectionOracle):
    HOUSE=0x31000000
    SCENERY_POOL=0x31900000

    def configure_constructor(self,case):
        self.case=case
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[]
        self.configure_selection(extract())
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[]
        houses=json.loads((ROOT/'game/assets/original/campaign/house-rules.json').read_text())
        self.unit_rows=list(houses['records'].values())
        self.string_keys={name:i+1 for i,name in enumerate(['house','farm',*houses['records']])}
        for i,row in enumerate(self.unit_rows):
            pointer=0x10fc241c+i*0x130
            self.set_integer(pointer,int(row['raw']['Rank']))
            self.set_integer(pointer+0x28,self.string_keys[row['raw']['Name Hash']])
            for key,value in row['values'].items():
                field=houses['native']['fields'][key]
                if field['arithmetic']=='int32':self.set_integer(pointer+field['offset'],int(value))
                else:self.set_float(pointer+field['offset'],value)
        self.index=case.get('index',18)
        self.stats=0x10fc241c+self.index*0x130
        self.cpu.mem_write(self.HOUSE,bytes(0x2d8))
        self.set_integer(0x10d94804,case.get('next_identity',0))
        self.set_float(0x105b2d08,25.)
        self.set_float(0x105b2d0c,36.)
        self.strings={}
        self.events=[]
        self.spatial=[]
        self.model_queries=[]
        self.field_queries=[]
        self.mine_queries=[]
        self.dirty_rectangles=[]
        self.cpu.mem_write(0x10f6e8d8,bytes(1024*128))
        self.adapters.update({
            0x10124660:lambda:self.return_integer(int(case.get('food_enabled',False))),
            0x101246f0:lambda:self.return_integer(int(case.get('ore_enabled',False))),
            0x10179880:self.clock_integer,
            0x10179810:lambda:self.return_float(case.get('seconds',12.5)),
            0x100b7580:lambda:self.return_integer(self.stats),
            0x100bb560:self.model,
            0x101a7d10:self.model_record,
            0x101b51e0:self.string,
            0x101b5260:self.string_id,
            0x1012c970:lambda:self.return_integer(), # terrain-region notification
            0x101450b0:lambda:self.return_float(case.get('raw_height',20.)),
            0x1012ec90:self.nearby,
            0x100cf550:self.beauty,
            0x100cf4b0:self.sample_blight,
            0x100e5eb0:self.dirty_rectangle, # renderer dirtiness notification
            0x100f1a00:self.register_spatial,
            0x102545c0:self.event,
            0x10001be0:self.mine_roll,
        })
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def clock_integer(self):
        value=self.case.get('clock',123456789)
        self.cpu.reg_write(self.regs.UC_X86_REG_EDX,value>>32)
        self.return_integer(value&0xffffffff)

    def model(self):
        self.model_queries.append(self.arguments(1)[0])
        self.return_integer(pop=4)

    def model_record(self):
        self.set_integer(self.SCRATCH+0xb00,0)
        self.return_integer(self.SCRATCH+0xb00,pop=4)

    def string(self):
        pointer=self.arguments(1)[0]
        value=bytes(self.cpu.mem_read(pointer,128)).split(b'\0',1)[0].decode('ascii')
        if value not in self.string_keys:raise ValueError('Unexpected source constructor string '+value)
        self.strings[value]=self.string_keys[value]
        self.set_integer(self.cpu.reg_read(self.regs.UC_X86_REG_ECX),self.strings[value])
        self.return_integer(pop=4)

    def string_id(self):
        self.return_integer(self.integer(self.cpu.reg_read(self.regs.UC_X86_REG_ECX)))

    def nearby(self):
        objects=self.case.get('nearby',[])
        for i,entry in enumerate(objects):
            pointer=self.SCENERY_POOL+i*0x200
            self.cpu.mem_write(pointer,bytes(0x200))
            self.set_integer(pointer+0x34,entry['type'])
            self.set_integer(pointer+0xac,entry.get('mode',0))
            self.set_integer(self.SCRATCH+0x2000+i*4,pointer)
            node=0x10c58e68+i*12
            self.set_integer(node,self.SCRATCH+0x2000+i*4)
            self.set_integer(node+4,node+12 if i+1<len(objects) else 0)
            self.set_integer(node+8,self.SCRATCH+0x1f00)
        self.return_integer(0x10c58e68 if objects else 0)

    def beauty(self):
        flag,x,z=self.arguments(3)
        if flag!=1:raise ValueError('Unexpected original surroundings field')
        self.field_queries.append(['beauty',x if x<0x80000000 else x-0x100000000,z if z<0x80000000 else z-0x100000000])
        self.return_float(self.case.get('beauty',0.))

    def sample_blight(self):
        x,z=self.arguments(2)
        self.field_queries.append(['blight',x if x<0x80000000 else x-0x100000000,z if z<0x80000000 else z-0x100000000])
        self.return_float(self.case.get('blight',0.))

    def mine_roll(self):
        self.mine_queries.append(list(struct.unpack('<2f',struct.pack('<2I',*self.arguments(2)))))
        self.return_float(self.case.get('mine_value',15.))

    def dirty_rectangle(self):
        self.dirty_rectangles.append([v if v<0x80000000 else v-0x100000000 for v in self.arguments(4)])
        self.return_integer(pop=16)

    def register_spatial(self):
        house,kind,x,z,radius,circular=self.arguments(6)
        if house!=self.HOUSE:raise ValueError('Unexpected source spatial registration')
        self.spatial.append(dict(kind=kind,position=list(struct.unpack('<2f',struct.pack('<2I',x,z))),
                                 radius=struct.unpack('<f',struct.pack('<I',radius))[0],circular=bool(circular)))
        self.return_integer(pop=24)

    def event(self):
        key,position,a,b,c=self.arguments(5)
        self.events.append(dict(key=key,position=list(struct.unpack('<3f',self.cpu.mem_read(position,12))),arguments=[a,b,c]))
        self.return_integer()

    def construct(self):
        position=self.case.get('position',[160.,122.,6.02,0.])
        floats=list(struct.unpack('<4I',struct.pack('<4f',*position)))
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.HOUSE)
        try:
            self.call(0x100bc660,[*floats,self.index,self.case.get('owner',0),0,self.case.get('kind',0),
                                  int(self.case.get('special',False)),self.case.get('silent',0),self.case.get('identity',0),self.case.get('configuration',0xffffffff),int(self.case.get('reuse',False))],limit=4000000)
        except Exception as error:
            raise ValueError(f"Constructor {self.case['name']} failed at {self.cpu.reg_read(self.regs.UC_X86_REG_EIP):#x}") from error
        return self.core_snapshot()

    def core_snapshot(self):
        offsets=[0x4,0x8,0xa,0x14,0x1c,0x20,0x30,0x38,0x48,0x4c,0x50,0x88,0xb0,0xb4,0xb8,0x118,0x124,0x1c0,
                 0xec,0x134,0x13c,0x144,0x154,0x1d4,0x1e8,0x1f4,0x244,0x248,0x24c,0x250,0x264,0x2c0,0x2cc]
        occupied=bytes(self.cpu.mem_read(0x10f6e8d8,1024*128))
        return dict(fields={hex(offset):self.cpu.mem_read(self.HOUSE+offset,2 if offset in [8,10] else 4).hex() for offset in offsets},
                    next_identity=self.integer(0x10d94804),events=self.events,spatial=self.spatial,
                    model_queries=self.model_queries,strings=self.strings,
                    slots=list(struct.unpack('<13i',self.cpu.mem_read(self.HOUSE+0x210,52))),
                    mine_queries=self.mine_queries,
                    dirty_rectangles=self.dirty_rectangles,
                    occupied=[index*8+bit for index,value in enumerate(occupied) if value
                              for bit in range(8) if value&(1<<bit)],
                    field_queries=dict(count=len(self.field_queries),sha256=hashlib.sha256(b''.join(
                        struct.pack('<iii',int(kind=='blight'),x,z) for kind,x,z in self.field_queries)).hexdigest()))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_house_constructor.json'))
    args=parser.parse_args()
    oracle=ConstructorOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    cases=[dict(name='first'),dict(name='flags',food_enabled=True,ore_enabled=True),
           dict(name='configuration',configuration=0x12345),dict(name='owner',owner=7),
           dict(name='identity',next_identity=0xfffffe),dict(name='identity_wrap',next_identity=0xffffff),
           dict(name='clock',clock=0x123456789ab,seconds=234.125),
           dict(name='rotation',position=[160.25,121.625,6.02,4.71238899230957]),
           dict(name='beautified',beauty=.75),dict(name='beauty_boundary',beauty=.5),
           dict(name='mixed_scenery',nearby=[dict(type=t,mode=m) for t,m in [(0,0),(14,2),(15,0),(15,2),(19,2),(20,0),(26,0)]]),
           dict(name='reuse',reuse=True),dict(name='location_boundary',position=[160.,122.,7.5,0.]),
           dict(name='farm',index=6,kind=1,special=True),dict(name='mine',index=12,kind=2,special=True),
           dict(name='special_rotation',index=22,position=[160.,122.,6.02,1.25])]
    cases.extend([dict(name='provided_identity',identity=0xff123456),dict(name='silent',silent=1),
                  dict(name='masked_identity_zero',identity=0xff000000),
                  dict(name='map_edge',position=[.25,.75,6.02,0.]),
                  dict(name='far_edge',position=[1023.5,1023.5,6.02,0.])])
    cases.extend(dict(name=f'source_row_{i}',index=i) for i in range(62))
    for case in cases:
        oracle.configure_constructor(case)
        case['expected']=oracle.construct()
        print(case['name'],'identity',case['expected']['fields']['0x88'],flush=True)
    source=extract()
    result={key:source[key] for key in ['source_sha256','table_sha256','executable_sha256']}
    result.update(cases=cases,adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip(),
                  native_routines={hex(a):oracle.image.read(a,b-a).hex() for a,b in [
                      (0x100bc660,0x100bcb72),(0x1003f610,0x1003f945),(0x100b7460,0x100b7536),(0x100b7900,0x100b79fb),
                      (0x10153dd0,0x10153dff),(0x1003e400,0x1003e505),(0x10357040,0x10357062)]})
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original house constructor:',len(cases),'cases')


if __name__=='__main__':main()
