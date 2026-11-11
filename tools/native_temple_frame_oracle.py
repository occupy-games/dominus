"""Compare the actual contiguous native temple pre-work frame, 10140d1e..10141204.

Worker counters and raw/world terrain are explicit inputs. Phase normalization,
passive work, forced timers, obstruction scan, decay and elevation decisions run
as original instructions. Spatial registration, type lookup and motion requests
are recorded services. No executable entrypoint, OS import or device is run.
"""
import copy
import json
import random
import struct

from tools.native_temple_footprint_oracle import FootprintOracle
from tools.native_temple_terrain_oracle import state as terrain_state,f32
from tools.native_scenery_oracle import ROOT
from tools.temple_terrain import extract
from tools.reward_dispatch import key


def state(**changes):
    result=terrain_state(handle=0,x=10.25,z=12.5,height=f32(6),footprint_width=2,
                         work_presence=0.,cooldown=0.,height_ceiling=8.,motion_handle=0)
    result.update(changes)
    for field in ['x','z','height','work_presence','cooldown','height_ceiling']:result[field]=f32(result[field])
    return result


class FrameOracle(FootprintOracle):
    START=0x10140d1e
    END=0x10141204
    FIELDS=dict(FootprintOracle.FIELDS,motion_handle=0x390)
    FLOATS=dict(FootprintOracle.FLOATS,x=0x278,z=0x27c,height=0x280,
                work_presence=0x314,cooldown=0x28,height_ceiling=0x1c)

    def configure_frame(self,content):
        self.configure_footprint(content)
        self.adapters.update({0x1013cd90:self.spatial,0x1025c150:self.world_ground,
                              0x101b51e0:self.construct_text,0x101b5260:self.hash_text,
                              0x1003fee0:self.type_lookup,0x101448b0:self.motion_locked,
                              0x10077050:self.move_vertical})
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def spatial(self):self.record('spatial_refresh',self.arguments(1));self.return_integer(pop=4)

    def world_ground(self):
        x,z,flag=self.arguments(3)
        self.record('world_ground',[struct.unpack('<f',struct.pack('<I',v))[0] for v in [x,z]]+[flag])
        self.return_float(self.case.get('world_ground',6.))

    def construct_text(self):
        pointer=self.arguments(1)[0]
        self.text=self.cpu.mem_read(pointer,5)
        assert self.text==b'boat\0'
        self.return_integer(pop=4)

    def hash_text(self):self.return_integer(key('boat'))

    def type_lookup(self):
        pointer=self.arguments(1)[0]
        assert self.integer(pointer)==self.integer(self.site+0x30c)
        self.record('is_boat')
        record=self.SCRATCH+0x8000
        self.set_integer(record+4,key('boat') if self.case.get('boat',False) else 123)
        self.return_integer(record,pop=4)

    def motion_locked(self):self.record('motion_locked');self.return_integer(int(self.case.get('motion_locked',False)))

    def move_vertical(self):
        handle,position,*values=self.arguments(7)
        assert handle==self.site+0x390 and position==self.site+0x278
        self.record('move_vertical',[struct.unpack('<f',struct.pack('<I',v))[0] for v in values[:4]]+[values[4]])
        self.return_integer()

    def run_frame(self,case):
        self.case=case;self.events=[];self.queries=[]
        current=case['state'];self.site=self.POOL+current['handle']*0x43c
        self.cpu.mem_write(self.site,bytes(0x43c))
        for name,offset in self.FIELDS.items():self.set_integer(self.site+offset,current[name])
        for name,offset in self.FLOATS.items():self.set_float(self.site+offset,current[name])
        self.cpu.mem_write(self.site+0x3f9,bytes([int(current['forced'])]))
        self.set_integer(0x10f9e8ec,self.SCRATCH+0x7000);self.set_integer(self.SCRATCH+0x7000,self.POOL)
        self.set_integer(0x10f9e8f0+current['handle']*4,case.get('workers',0))
        self.prepare_extra()
        frame=self.STACK+0x80000;self.set_float(frame+8,case.get('delta',.1))
        for reg,value in [(self.regs.UC_X86_REG_ESP,frame-0x200),(self.regs.UC_X86_REG_EBP,frame),
                          (self.regs.UC_X86_REG_ESI,self.site),(self.regs.UC_X86_REG_EBX,0)]:self.cpu.reg_write(reg,value)
        # The preceding timed-affiliation branch leaves its native 5.0
        # constant in ST(0). Preserve that actual incoming FPU frame.
        start=b'\xdb\xe3'
        if self.START==0x10140d1e:start+=b'\xdd\x05'+struct.pack('<I',0x104ad750)
        self.cpu.mem_write(self.SCRATCH+0x700,start)
        self.cpu.emu_start(self.SCRATCH+0x700,self.SCRATCH+0x700+len(start))
        self.cpu.emu_start(self.START,self.END,count=5000000)
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=self.END:raise ValueError('Temple frame instruction budget exhausted')
        return dict(state=self.snapshot(),events=copy.deepcopy(self.events),queries=copy.deepcopy(self.queries))

    def prepare_extra(self):pass


def cases(content):
    examples=[]
    for phase in range(9):
        for forced in [False,True]:
            for mode in [0,1]:
                for ground in [19,21]:
                    examples.append(dict(name=f'phase_{phase}_{forced}_{mode}_{ground}',state=state(phase=phase,forced=forced,transition_mode=mode),ground=dict(default=ground),workers=3,is_settlement=True))
    for workers in [0,1,3,0x7fffffff,0x80000000,0xffffffff]:
        for presence in [-.1,0,.999,1,1.2]:
            examples.append(dict(name=f'presence_{workers}_{presence}',state=state(work_presence=presence),workers=workers,ground=dict(default=19)))
    for current in [4.,6.,6.01,8.]:
        for ceiling in [5.,8.]:
            for mode in [0,1]:
                for moving in [0,1]:
                    for locked in [False,True]:
                        examples.append(dict(name=f'elevation_{current}_{ceiling}_{mode}_{moving}_{locked}',state=state(height=current,height_ceiling=ceiling,transition_mode=mode,motion_handle=moving),ground=dict(default=19),motion_locked=locked))
    for boat in [False,True]:
        for cooldown in [-.1,0,.05,.1,.5]:
            examples.append(dict(name=f'boat_cooldown_{boat}_{cooldown}',state=state(height=5.6,transition_mode=0,cooldown=cooldown),ground=dict(default=19),boat=boat))
    rng=random.Random(0x10140d1e)
    for index in range(100):
        examples.append(dict(name=f'arithmetic_{index}',state=state(handle=rng.choice([0,2,17]),phase=rng.choice([5,6,7,8]),transition_mode=rng.choice([0,1]),
                             forced=bool(index%2),timer=f32(rng.random()*5),progress=f32(rng.random()*50),required=f32(1+rng.random()*60),
                             height=f32(5+rng.random()*3),height_ceiling=f32(5+rng.random()*4),work_presence=f32(rng.random()),cooldown=f32(rng.random())),
                             delta=f32(rng.random()),workers=rng.randrange(0,20),ground=dict(default=rng.choice([19,21])),world_ground=f32(5+rng.random()*3)))
    return examples


def main():
    content=extract();oracle=FrameOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_frame(content)
    examples=cases(content)
    for case in examples:
        try:case['expected']=oracle.run_frame(case)
        except Exception as error:raise ValueError('Original temple frame '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    sequences=[]
    for kind in [123,content['rules']['special_types'][0]]:
        for forced in [False,True]:
            sequence=dict(initial=state(generic_type=kind,forced=forced),steps=[])
            current=copy.deepcopy(sequence['initial'])
            for index in range(24):
                step=dict(ground=dict(default=19 if 4<=index<8 or index>=16 else 21),world_ground=f32(6 if index<12 else 5.5),
                          delta=.25,workers=2,is_settlement=True)
                case=dict(step,state=current)
                expected=oracle.run_frame(case);current=copy.deepcopy(expected['state'])
                sequence['steps'].append(dict(step,expected=expected))
            sequences.append(sequence)
    fixture=dict(executable_sha256=content['executable_sha256'],cases=examples,sequences=sequences,
                 native_routines=content['native_routines'],adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_temple_frame.json').write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    print('Original temple frame:',len(examples),'cases,',sum(len(s['steps']) for s in sequences),'sequence steps',flush=True)


if __name__=='__main__':main()
