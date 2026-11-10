"""Run original state entry with explicit clip resolution/length and visual sinks.

The whole native entry routine and stack-cookie check execute. Clip selection,
duration and animation/heading delivery are adapters. This observes logical
entry timing, not asset availability, state updates, navigation or active work.
"""
import argparse
import json
import struct

from tools.action_entry import extract
from tools.native_scenery_oracle import Oracle, ROOT


class EntryOracle(Oracle):
    ACTOR=0x31800000
    CHANNEL=0x31801000

    def configure_entry(self,case):
        self.case=case
        for handle in self.handles:self.cpu.hook_del(handle)
        self.log=[]
        self.cpu.mem_write(self.ACTOR,bytes(0x200))
        self.set_integer(self.ACTOR+0x104,self.CHANNEL if case.get('has_channel',True) else 0)
        self.set_integer(self.ACTOR+0x4c,19)
        self.cpu.mem_write(self.ACTOR+0x69,b'\x01')
        for offset,value in [(0xd4,case.get('orientation',.75)),(0x130,case.get('orientation_rate',.5)),(0x54,3.),(0x58,7.25),(0x60,99.)]:self.set_float(self.ACTOR+offset,value)
        self.set_integer(self.ACTOR+0x64,99)
        pointer=0x106f30a8+case.get('action',0)*0xcf8+case.get('index',0)*0xa4
        self.cpu.mem_write(pointer,bytes(0xa4))
        self.set_integer(pointer+0x38,case.get('update_type',0))
        self.cpu.mem_write(pointer+0x58,bytes([int(case.get('loop',False))]))
        self.adapters={0x10002150:self.resolve,0x10035fd0:self.duration,0x1015fd00:self.orientation,0x1015fda0:self.animate}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def resolve(self):
        actor,profile=self.arguments(2)
        if actor!=self.ACTOR:raise ValueError('Unexpected source entry owner')
        self.log.append(['resolve',self.integer(actor+0x4c),bool(self.cpu.mem_read(actor+0x69,1)[0]),profile])
        if 'resolve_loop' in self.case:self.cpu.mem_write(self.cpu.reg_read(self.regs.UC_X86_REG_ECX)+0x58,bytes([int(self.case['resolve_loop'])]))
        self.return_integer(self.case.get('clip',14),pop=8)

    def duration(self):
        clip=self.arguments(1)[0]
        self.log.append(['duration',clip if clip<0x80000000 else clip-0x100000000])
        self.return_float(self.case.get('duration',2.5))

    def orientation(self):
        self.log.append(['orientation',*struct.unpack('<2f',struct.pack('<2I',*self.arguments(2)))])
        self.return_integer(pop=8)

    def animate(self):
        actor,clip,loop,speed,blend=self.arguments(5)
        if actor!=self.ACTOR:raise ValueError('Unexpected source playback owner')
        self.log.append(['animate',clip if clip<0x80000000 else clip-0x100000000,bool(loop&255),*struct.unpack('<2f',struct.pack('<2I',speed,blend))])
        self.return_integer(pop=20)

    def enter(self):
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.ACTOR)
        result=self.call(0x10067620,[self.case.get('action',0),self.case.get('index',0),self.case.get('profile',4)])
        clip=self.integer(self.ACTOR+0x64)
        return dict(result=bool(result&255),log=self.log,actor=dict(step=self.integer(self.ACTOR+0x4c),entry_done=bool(self.cpu.mem_read(self.ACTOR+0x69,1)[0]),
                    has_channel=self.case.get('has_channel',True),clip=clip if clip<0x80000000 else clip-0x100000000,
                    orientation=self.float(self.ACTOR+0xd4),orientation_rate=self.float(self.ACTOR+0x130),
                    clip_duration=self.float(self.ACTOR+0x60),clip_phase=self.float(self.ACTOR+0x54),clip_time=self.float(self.ACTOR+0x58)))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_action_entry.json'))
    args=parser.parse_args()
    content=extract()
    oracle=EntryOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    cases=[dict(name='first'),dict(name='no_channel',has_channel=False),dict(name='loop',loop=True),
           dict(name='fractional',duration=.3,orientation=.123456,orientation_rate=1.234567),
           dict(name='negative_rate',orientation_rate=-3.5),dict(name='zero_duration',duration=0.),
           dict(name='negative_duration',duration=-1.),dict(name='last_step',index=19,profile=9),
           dict(name='last_clip',clip=346,update_type=200),dict(name='missing_animation_update',clip=347,update_type=200),
           dict(name='missing_navigation_update',clip=347,update_type=4),dict(name='missing_lower_update',clip=347,update_type=199),
           dict(name='missing_higher_update',clip=348,update_type=201),dict(name='missing_no_channel',clip=347,update_type=200,has_channel=False),
           dict(name='negative_clip',clip=-1,update_type=200),dict(name='by_value_loop',resolve_loop=True)]
    for row in content['records']:
        if row['available']:cases.append(dict(name=row['name']+'_'+str(row['index']),action=row['action'],index=row['index'],update_type=row['update_type'],loop=row['loop']))
    for case in cases:
        oracle.configure_entry(case)
        case['expected']=oracle.enter()
    result={key:content[key] for key in ['source_sha256','executable_sha256','tables','native_routines']}
    result.update(cases=cases,scope=__doc__.strip(),adapters=[hex(a) for a in sorted(oracle.adapters)])
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original action entry:',len(cases),'cases')


if __name__=='__main__':main()
