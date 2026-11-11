"""Execute original building foundation scan, rounding, fabs and sample ordering.

Actual 1003b690 instructions execute, including inclusive loops and stored
float32 differences. Terrain-overlay availability, overlay reads and fallback
ground reads are explicit services. No executable entrypoint/device is run.
"""
import copy
import json
import random
import struct

from tools.native_scenery_oracle import Oracle,ROOT
from tools.native_temple_terrain_oracle import f32
from tools.building_foundation import extract


def state(**changes):
    result=dict(position=[10.25,12.5,6.],anchor_step=20,nav_size=2,uneven_count=999)
    result.update(changes);result['position']=[f32(v) for v in result['position']]
    return result


class FoundationOracle(Oracle):
    def configure_foundation(self):
        self.configure(b'',b'',b'',[])
        self.adapters={0x100d0e90:self.overlay_owner,0x1015df40:self.overlay,0x101450b0:self.ground}
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_bounds,begin=0x1003b75c,end=0x1003b75c))

    def foundation_event(self,name,args=()):self.events.append([name,list(args),self.integer(self.body+0x80)])

    def overlay_owner(self):
        self.foundation_event('terrain_overlay')
        self.return_integer(self.GRIDS if self.case.get('overlay_available',False) else 0)

    def overlay(self):
        x,z,target=self.arguments(3)
        x=x-0x100000000 if x>=0x80000000 else x;z=z-0x100000000 if z>=0x80000000 else z
        self.foundation_event('overlay',[x,z])
        lookup=self.case.get('overlay',{});value=lookup.get('values',{}).get(f'{x},{z}',lookup.get('default',dict(found=False,height=0.)))
        self.set_float(target,value.get('height',0.));self.return_integer(int(value['found']),pop=12)

    def ground(self):
        x,z=self.arguments(2)
        x=x-0x100000000 if x>=0x80000000 else x;z=z-0x100000000 if z>=0x80000000 else z
        self.foundation_event('ground',[x,z])
        lookup=self.case.get('ground',{});value=lookup.get('values',{}).get(f'{x},{z}',lookup.get('default',0.))
        self.return_float(value)

    def observe_bounds(self,cpu,address,size,user):
        frame=self.cpu.reg_read(self.regs.UC_X86_REG_EBP)
        def integer(value):return value-0x100000000 if value>=0x80000000 else value
        x0=integer(self.integer(frame-0x14));x1=integer(self.integer(frame-8))
        z0=integer(self.cpu.reg_read(self.regs.UC_X86_REG_EDI));z1=integer(self.integer(frame-0x10))
        self.region=[x0,z0,max(0,x1-x0+1),max(0,z1-z0+1)]

    def write_foundation(self,current):
        for field,offset in [('anchor_step',0xcc),('nav_size',0xe0),('uneven_count',0x80)]:self.set_integer(self.body+offset,current[field])
        for index,value in enumerate(current['position']):self.set_float(self.body+0x3c+4*index,value)

    def run_foundation(self,case):
        self.case=case;self.events=[];self.body=self.POOL;self.region=[]
        self.cpu.mem_write(self.body,bytes(0x160));self.write_foundation(case['state'])
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.body)
        self.call(0x1003b690,limit=5000000)
        result=copy.deepcopy(case['state']);result['uneven_count']=self.integer(self.body+0x80)
        return dict(state=result,events=copy.deepcopy(self.events),bounds=self.region)


def cases():
    examples=[]
    for width in [-1,0,1,2,3,4,8]:
        for fraction in [-.75,-.5,-.250001,-.25,0,.249999,.25,.5,.75]:
            for raw in [19.,20.,21.]:
                examples.append(dict(name=f'grid_{width}_{fraction}_{raw}',state=state(position=[10+fraction,12-fraction,6.],nav_size=width),ground=dict(default=raw)))
    for raw in [-.10000000894069672,-.10000000149011612,-.09999999403953552,0.,.09999999403953552,.10000000149011612,.10000000894069672]:
        examples.append(dict(name=f'tolerance_{raw}',state=state(position=[0.,0.,0.],anchor_step=0,nav_size=1),ground=dict(default=raw)))
    for anchor in [16777217,2147483647,-2147483648]:
        examples.append(dict(name=f'anchor_{anchor}',state=state(anchor_step=anchor),ground=dict(default=f32(anchor))))
    for available in [False,True]:
        for found in [False,True]:
            for raw in [19.,20.,21.]:
                examples.append(dict(name=f'override_{available}_{found}_{raw}',state=state(),overlay_available=available,
                    overlay=dict(default=dict(found=found,height=raw)),ground=dict(default=20.)))
    examples.append(dict(name='mixed_overrides',state=state(),overlay_available=True,
                         overlay=dict(default=dict(found=False,height=999.),values={'10,12':dict(found=True,height=20.),'11,13':dict(found=True,height=19.)}),ground=dict(default=21.)))
    rng=random.Random(0x1003b690)
    for index in range(64):
        current=state(position=[f32(-4+rng.random()*20),f32(-4+rng.random()*20),6.],nav_size=rng.randrange(9),anchor_step=rng.randrange(-1,30))
        ground={f'{x},{z}':float(rng.randrange(0,32)) for z in range(-10,25) for x in range(-10,25)}
        overlay={f'{x},{z}':dict(found=bool(rng.randrange(2)),height=float(rng.randrange(0,32))) for z in range(-10,25) for x in range(-10,25)}
        examples.append(dict(name=f'arithmetic_{index}',state=current,overlay_available=bool(index%2),ground=dict(default=0.,values=ground),overlay=dict(default=dict(found=False,height=0.),values=overlay)))
    return examples


def main():
    content=extract();oracle=FoundationOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_foundation()
    examples=cases()
    for case in examples:
        try:case['expected']=oracle.run_foundation(case)
        except Exception as error:raise ValueError('Original foundation '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
        # Keep only supplied samples actually requested by the native scan.
        # Unexpected extra reads still fail the independent event-order check.
        for name in ['ground','overlay']:
            if 'values' in case.get(name,{}):
                used={f'{event[1][0]},{event[1][1]}' for event in case['expected']['events'] if event[0]==name}
                case[name]['values']={key:value for key,value in case[name]['values'].items() if key in used}
    sequences=[]
    for available in [False,True]:
        sequence=dict(initial=state(),steps=[]);current=copy.deepcopy(sequence['initial'])
        for index in range(24):
            step=dict(position=[float(index)-4,12.5,6.],overlay_available=available,ground=dict(default=20. if index%6 in [0,1] else 19.),
                      overlay=dict(default=dict(found=index%4!=0,height=20. if index%4 in [1,2] else 21.)))
            current['position']=step['position']
            expected=oracle.run_foundation(dict(step,state=current));current=copy.deepcopy(expected['state'])
            sequence['steps'].append(dict(step,expected=expected))
        sequences.append(sequence)
    fixture=dict(executable_sha256=content['executable_sha256'],rules=content['rules'],cases=examples,sequences=sequences,
                 native_routines=content['native_routines'],adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_building_foundation.json').write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    print('Original building foundations:',len(examples),'cases,',sum(len(s['steps']) for s in sequences),'steps',flush=True)


if __name__=='__main__':main()
