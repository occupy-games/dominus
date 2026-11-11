"""Execute original house terrain, damage/recovery and construction frame.

Original 100bb96b..100bbbdb executes with actual foundation scan and powf.
Also captures 100bb9a8 entry with an explicit already-sampled foundation count.
Terrain, target/stat lookup, model/effect/economy, notices and clock are explicit
adapters. The remaining house lifetime and executable entrypoint do not run.
"""
import copy
import json
import random
import struct

from tools.native_scenery_oracle import ROOT
from tools.native_building_foundation_oracle import FoundationOracle,state as foundation_state
from tools.native_temple_terrain_oracle import f32
from tools.building_foundation import extract as foundation_content
from tools.house_terrain_frame import extract


def state(**changes):
    result=foundation_state(uneven_count=0)
    result.update(state=0,forced=False,reference_attached=False,handle=3,identity=0x8100002a,workers=1,
                  variant=2,status_mode=1,progress=1.25,damage_timer=0.,post_complete_timer=4.,created_clock=12345,
                  restore_requested=0,appearance_dirty=0,completed_dirty=0)
    result.update(changes)
    for field in ['progress','damage_timer','post_complete_timer']:result[field]=f32(result[field])
    return result


class HouseFrameOracle(FoundationOracle):
    HOUSE=0x31000000
    FIELDS=dict(state=0x134,variant=0x13c,status_mode=0x2c,identity=0x88,workers=0x188,
                restore_requested=0x170,appearance_dirty=0x1f8,completed_dirty=0x1e4,uneven_count=0xf4)
    FLOATS=dict(progress=0x38,damage_timer=0x44,post_complete_timer=0x50)
    EVENT_FIELDS=['state','progress','damage_timer','variant','uneven_count','restore_requested',
                  'appearance_dirty','completed_dirty','post_complete_timer','created_clock']

    def configure_house_frame(self):
        self.configure_foundation()
        self.adapters.update({0x100b7e80:self.construction_target,0x100b7580:self.work_exponent,
                              0x100b5ad0:lambda:self.simple('stop_damage_effect'),0x100b5a70:lambda:self.simple('start_damage_effect'),
                              0x100bb6e0:lambda:self.simple('refresh_variant'),0x100b8670:lambda:self.simple('destruction_economy'),
                              0x10100890:self.house_event,0x102545c0:self.sound,0x10245d30:self.complete_hook,0x10179880:self.clock})
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_bounds,begin=0x1003b75c,end=0x1003b75c))

    def snapshot(self):
        result=copy.deepcopy(self.case['state'])
        for field,offset in self.FIELDS.items():result[field]=self.integer(self.HOUSE+offset)
        for field,offset in self.FLOATS.items():result[field]=self.float(self.HOUSE+offset)
        result['created_clock']=struct.unpack('<Q',self.cpu.mem_read(self.HOUSE+0x48,8))[0]
        return result

    def foundation_event(self,name,args=()):
        state=self.snapshot();self.events.append([name,list(args),[state[field] for field in self.EVENT_FIELDS]])

    def simple(self,name):self.foundation_event(name);self.return_integer()

    def construction_target(self):
        self.foundation_event('construction_target')
        for field,value in self.case.get('target_changes',{}).items():self.set_float(self.HOUSE+self.FLOATS[field],value)
        self.return_float(self.case.get('target',5.))

    def work_exponent(self):
        self.foundation_event('work_exponent');pointer=self.SCRATCH+0x8000
        self.set_float(pointer+0x98,self.case.get('exponent',.7));self.return_integer(pointer)

    def house_event(self):
        owner,kind,one,house=self.arguments(4)
        assert house==self.HOUSE
        self.foundation_event('house_event',[owner,kind,one,self.case['state']['handle']]);self.return_integer()

    def sound(self):
        kind,position,zero,priority,flags=self.arguments(5)
        assert position==self.HOUSE+0xb0
        self.foundation_event('sound',[kind,[self.float(position+4*i) for i in range(3)],zero,priority,flags]);self.return_integer()

    def complete_hook(self):
        pointer,handle=self.arguments(2)
        name=bytes(self.cpu.mem_read(pointer,80)).split(b'\0')[0].decode()
        self.foundation_event('hook',[name,handle]);self.return_integer()

    def clock(self):
        self.foundation_event('clock',self.arguments(1));value=self.case.get('clock',0x123456789ab)
        self.cpu.reg_write(self.regs.UC_X86_REG_EDX,value>>32);self.return_integer(value&0xffffffff)

    def write_house(self,current):
        self.cpu.mem_write(self.HOUSE,bytes(0x2d8));self.write_foundation(current)
        for field,offset in self.FIELDS.items():self.set_integer(self.HOUSE+offset,current[field])
        for field,offset in self.FLOATS.items():self.set_float(self.HOUSE+offset,current[field])
        self.set_integer(self.HOUSE+0x1cc,self.GRIDS if current['reference_attached'] else 0)
        self.cpu.mem_write(self.HOUSE+0x2a8,bytes([int(current['forced'])]))
        self.cpu.mem_write(self.HOUSE+0x48,struct.pack('<Q',current['created_clock']))
        self.set_integer(0x10fcd474,self.HOUSE-current['handle']*0x2d8)

    def run_frame(self,case):
        self.case=case;self.events=[];self.region=[];self.body=self.HOUSE+0x74
        self.write_house(case['state'])
        frame=self.STACK+0x80000;delta=case.get('delta',.25);self.set_float(frame+8,delta)
        for register,value in [(self.regs.UC_X86_REG_ESP,frame-0x200),(self.regs.UC_X86_REG_EBP,frame),
                               (self.regs.UC_X86_REG_ESI,self.HOUSE),(self.regs.UC_X86_REG_EBX,0),(self.regs.UC_X86_REG_EDI,1)]:self.cpu.reg_write(register,value)
        code=b'\xdb\xe3'
        if not case.get('frame',True):code+=b'\xd9\x05'+struct.pack('<I',frame+8)
        start=self.SCRATCH+0x700;self.cpu.mem_write(start,code);self.cpu.ctl_remove_cache(start,start+0x20)
        self.cpu.emu_start(start,start+len(code))
        self.cpu.emu_start(0x100bb96b if case.get('frame',True) else 0x100bb9a8,0x100bbbdb,count=5000000)
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=0x100bbbdb:raise ValueError('House terrain frame instruction budget exhausted')
        return dict(state=self.snapshot(),events=copy.deepcopy(self.events),bounds=self.region)


def cases():
    examples=[]
    for phase in [0,1,2,3,4,7]:
        for attached in [False,True]:
            for forced in [False,True]:
                for raw in [19.,20.,21.]:
                    examples.append(dict(name=f'frame_{phase}_{attached}_{forced}_{raw}',state=state(state=phase,reference_attached=attached,forced=forced,uneven_count=0 if raw==20 else 4),ground=dict(default=raw)))
    for attached in [False,True]:
        limit=.5 if attached else 1.
        for timer in [limit-.125,limit,limit+.125]:
            for variant in [0,1,0xffffffff]:
                for mode in [0,1,2,3]:
                    examples.append(dict(name=f'threshold_{attached}_{timer}_{variant}_{mode}',frame=False,
                        state=state(state=2,reference_attached=attached,uneven_count=4,damage_timer=timer,variant=variant,status_mode=mode),delta=0.))
    for progress in [0.,4.999999523162842,5.,5.000000476837158,9.]:
        for workers in [0,1,2,3,0x80000000,0xffffffff]:
            examples.append(dict(name=f'work_{progress}_{workers}',frame=False,state=state(progress=progress,workers=workers,handle=65534 if workers>0x7fffffff else 3),delta=.25))
    examples.extend([
        dict(name='damage_uses_saved_progress',frame=False,state=state(progress=3.,uneven_count=4),target_changes=dict(progress=0.)),
        dict(name='recovery_reads_new_timer',frame=False,state=state(state=2,damage_timer=.75),target_changes=dict(damage_timer=.25)),
        dict(name='completion_uses_saved_progress',frame=False,state=state(progress=6.,workers=0),target_changes=dict(progress=0.)),
        dict(name='overlay_prevents_damage',state=state(),overlay_available=True,overlay=dict(default=dict(found=True,height=20.)),ground=dict(default=21.)),
        dict(name='lowered_override_starts_damage',state=state(),overlay_available=True,overlay=dict(default=dict(found=True,height=19.)),ground=dict(default=20.)),
        dict(name='one_variant_per_frame',frame=False,state=state(state=2,variant=7,uneven_count=16),delta=100.),
    ])
    rng=random.Random(0x100bb96b)
    for index in range(64):
        raw=rng.choice([19.,20.,21.]);phase=rng.choice([0,1,2,3,4])
        examples.append(dict(name=f'arithmetic_{index}',state=state(state=phase,forced=bool(index%2),reference_attached=bool(index%3),
                             damage_timer=rng.random()*2,progress=rng.random()*8,workers=rng.randrange(0,64),uneven_count=rng.randrange(0,17),nav_size=rng.randrange(1,6)),
                             ground=dict(default=raw),delta=f32(rng.random()),target=f32(1+rng.random()*8),exponent=f32(rng.random()*1.5)))
    return examples


def main():
    content=extract();foundation=foundation_content()
    oracle=HouseFrameOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_house_frame()
    examples=cases()
    for case in examples:
        try:case['expected']=oracle.run_frame(case)
        except Exception as error:raise ValueError('Original house frame '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    sequences=[]
    for attached in [False,True]:
        sequence=dict(initial=state(reference_attached=attached,variant=3,progress=1.),steps=[]);current=copy.deepcopy(sequence['initial'])
        for index in range(32):
            uneven=3<=index<11
            inputs=dict(forced=7<=index<9)
            if attached:inputs['uneven_count']=4 if uneven else 0
            current.update(inputs)
            step=dict(inputs=inputs,delta=.25,ground=dict(default=19. if uneven else 20.))
            expected=oracle.run_frame(dict(step,state=current));current=copy.deepcopy(expected['state'])
            sequence['steps'].append(dict(step,expected=expected))
        sequences.append(sequence)
    routines = {address:content['native_routines'][address] for address in ['0x100bb96b','0x10356fd0']}
    fixture=dict(executable_sha256=content['executable_sha256'],cases=examples,sequences=sequences,
                 native_routines=dict(foundation['native_routines'],**routines),adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_house_terrain_frame.json').write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    print('Original house terrain/work frame:',len(examples),'cases,',sum(len(s['steps']) for s in sequences),'steps',flush=True)


if __name__=='__main__':main()
