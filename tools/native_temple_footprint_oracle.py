"""Execute the original discrete temple footprint scan and composed decay block.

Native scan bounds, rounding, sample order and obstruction comparison execute.
Raw terrain lookup and unused terrain-owner access are in-memory adapters.
The composed cases also execute the original phase/decay block, including its
unadapted call to the footprint scan. No executable entrypoint or device runs.
"""
import copy
import json
import random
import struct

from tools.native_temple_terrain_oracle import TempleTerrainOracle,state,f32
from tools.native_scenery_oracle import ROOT
from tools.temple_terrain import extract


class FootprintOracle(TempleTerrainOracle):
    def configure_footprint(self,content):
        self.configure_terrain(content)
        del self.adapters[0x1003b550]
        self.adapters.update({0x100d0e90:lambda:self.return_integer(),0x101450b0:self.ground})
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def ground(self):
        x,z=[v-0x100000000 if v>=0x80000000 else v for v in self.arguments(2)]
        value=self.case.get('ground',{}).get('values',{}).get(f'{x},{z}',self.case.get('ground',{}).get('default',0))
        self.queries.append([x,z,f32(value)])
        self.return_float(value)

    def place(self,site):
        self.set_float(self.site+0x278,site['x']);self.set_float(self.site+0x27c,site['z']);self.set_float(self.site+0x280,site['height'])
        self.set_integer(self.site+0x31c,site['footprint_width'])

    def run_footprint(self,case):
        self.case=case;self.queries=[];self.site=self.POOL
        self.cpu.mem_write(self.site,bytes(0x43c));self.place(case['site'])
        self.set_integer(self.site+0x2bc,999)
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.site+0x23c)
        self.call(0x1003b550,limit=5000000)
        return dict(count=self.integer(self.site+0x2bc),queries=copy.deepcopy(self.queries))

    def run_composed(self,case):
        self.case=case;self.events=[];self.queries=[];self.site=self.POOL
        self.cpu.mem_write(self.site,bytes(0x43c))
        for name,offset in self.FIELDS.items():self.set_integer(self.site+offset,case['state'][name])
        for name,offset in self.FLOATS.items():self.set_float(self.site+offset,case['state'][name])
        self.place(case['site'])
        self.cpu.mem_write(self.site+0x3f9,bytes([int(case['state']['forced'])]))
        frame=self.STACK+0x80000;self.set_float(frame+8,case.get('delta',.1))
        for reg,value in [(self.regs.UC_X86_REG_ESP,frame-0x200),(self.regs.UC_X86_REG_EBP,frame),(self.regs.UC_X86_REG_ESI,self.site),(self.regs.UC_X86_REG_EBX,0),(self.regs.UC_X86_REG_EDI,5)]:self.cpu.reg_write(reg,value)
        self.cpu.mem_write(self.SCRATCH+0x700,b'\xdb\xe3');self.cpu.emu_start(self.SCRATCH+0x700,self.SCRATCH+0x702)
        self.cpu.emu_start(0x10140ded,0x101410c8,count=5000000)
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=0x101410c8:raise ValueError('Composed temple terrain budget exhausted')
        return dict(state=self.snapshot(),events=copy.deepcopy(self.events),queries=copy.deepcopy(self.queries))


def cases():
    result=[]
    for width in [0,1,2,3,4,8]:
        for fraction in [-.75,-.5,-.250001,-.25,0,.249999,.25,.5,.75]:
            for raw in [19,21]:
                result.append(dict(name=f'grid_{width}_{fraction}_{raw}',site=dict(x=f32(10+fraction),z=f32(12-fraction),height=f32(20*.30000001192092896),footprint_width=width),ground=dict(default=raw)))
    for value in [20.,20.099998474121094,20.100000381469727,21.]:
        result.append(dict(name=f'threshold_{value}',site=dict(x=-.5,z=-.25,height=f32(20*.30000001192092896),footprint_width=2),ground=dict(default=value)))
    rng=random.Random(0x1003b550)
    for index in range(50):
        values={f'{x},{z}':rng.randint(0,40) for z in range(0,22) for x in range(0,22)}
        result.append(dict(name=f'irregular_{index}',site=dict(x=f32(5+rng.random()*8),z=f32(5+rng.random()*8),height=f32(rng.randint(1,30)*.30000001192092896),footprint_width=rng.choice([1,2,3,5,8,16])),ground=dict(default=0,values=values)))
    return result


def main():
    content=extract();oracle=FootprintOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_footprint(content)
    examples=cases()
    for case in examples:
        try:case['expected']=oracle.run_footprint(case)
        except Exception as error:raise ValueError('Original footprint '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    composed=[];sequences=[]
    for kind in [123,*content['rules']['special_types']]:
        site=dict(x=10.25,z=12.5,height=f32(20*.30000001192092896),footprint_width=2)
        for phase in [0,1,2,5,6,7,8]:
            for raw in [19,21]:
                case=dict(name=f'composed_{kind}_{phase}_{raw}',site=site,state=state(phase=phase,generic_type=kind,footprint_width=2),ground=dict(default=raw),is_settlement=True)
                case['expected']=oracle.run_composed(case);composed.append(case)
        sequence=dict(site=site,initial=state(generic_type=kind,footprint_width=2),steps=[])
        current=copy.deepcopy(sequence['initial'])
        for index in range(24):
            ground=dict(default=19 if 3<=index<6 or 12<=index<15 else 21)
            case=dict(site=site,state=current,ground=ground,delta=f32(.25),is_settlement=True)
            expected=oracle.run_composed(case);current=copy.deepcopy(expected['state'])
            sequence['steps'].append(dict(ground=ground,expected=expected))
        sequences.append(sequence)
    fixture=dict(executable_sha256=content['executable_sha256'],cases=examples,composed=composed,sequences=sequences,
                 native_routines=content['native_routines'],adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_temple_footprint.json').write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    print('Original temple footprint:',len(examples),'scans,',len(composed),'composed cases,',sum(len(s['steps']) for s in sequences),'sequence steps',flush=True)


if __name__=='__main__':main()
