"""Execute original action advancement with actual selection, entry, RNG and refs.

Source controls are injected. Validity, clip resolution/length, target position,
decision queuing, navigation reset and visual/audio delivery are adapters. Full
movement/work updates and non-house/plot reference lifetimes are not claimed.
"""
import argparse
import json
import struct

from tools.action_controller import extract
from tools.action_entry import extract as entries
from tools.action_sequences import extract as sequences
from tools.native_action_entry_oracle import EntryOracle
from tools.native_action_sequence_oracle import SequenceOracle
from tools.native_scenery_oracle import ROOT


def compile_action(source, entry_data, controller, identity):
    action=next(a for a in source['actions'] if a['id']==identity)
    flags=next(a for a in controller['actions'] if a['id']==identity)
    states=[dict(source['default_state'],**controller['default_state']) for _ in range(20)]
    for state in action['states']:states[state['index']].update({key:state[key] for key in ['name','next','skip_to','skip_probability']})
    for row in flags['states']:states[row['index']].update(row)
    for row in entry_data['records']:
        if row['action']==identity and row['available']:states[row['index']].update({key:row[key] for key in ['update_type','loop']})
    return dict(states=states,looping=flags['looping'])


class ControllerOracle(EntryOracle,SequenceOracle):
    CHANNEL=0x31803000
    TLS=0x31802000
    CACHED=0x31804000
    REFERENCE=0x31805000
    FOLLOWER=0x31806000
    HOUSE=0x31000000
    PATH=0x31807000

    def reference(self,spec):
        identity=spec.get('identity',0x01000001)
        entity=spec.get('entity',0)
        return struct.pack('<IIffI',identity,self.HOUSE+entity*0x2d8 if entity>=0 else 0,*spec.get('position',[-1.,-1.]),1)

    def configure_controller(self,case,compiled):
        self.configure_entry(case)
        for handle in self.handles:self.cpu.hook_del(handle)
        self.queries=[]
        self.random_calls=0
        self.set_integer(self.TLS+0x14,case.get('seed',1))
        self.set_integer(self.ACTOR+0x7c,case.get('action',103))
        self.set_integer(self.ACTOR+0x4c,case.get('begin',0))
        self.set_integer(self.ACTOR+0x6c,case.get('phase',3))
        self.set_integer(self.ACTOR+0x108,case.get('profile',4))
        self.cpu.mem_write(self.ACTOR+0x68,bytes([int(case.get('failed',False))]))
        self.cpu.mem_write(self.ACTOR+0x10,b'\x03')
        self.cpu.mem_write(self.ACTOR+0xe8,b'\x07')
        self.set_float(self.ACTOR+0xc0,9.)
        for i,value in enumerate(case.get('position',[157.,119.,6.])):self.set_float(self.ACTOR+0x70+i*4,value)
        self.set_integer(self.ACTOR+0x100,self.FOLLOWER)
        self.cpu.mem_write(self.FOLLOWER+0x34,struct.pack('<H',case.get('voice',0)<<15))
        self.set_integer(self.ACTOR+0xf4,self.PATH)
        self.cpu.mem_write(self.HOUSE,bytes(0x400))
        self.set_integer(self.HOUSE+0x88,case.get('house_identity',0x01000001))
        self.set_integer(self.HOUSE+0x134,case.get('house_state',0))
        self.set_integer(self.HOUSE+0x2fc,case.get('completion_state',0))
        self.cpu.mem_write(self.REFERENCE,self.reference(case.get('target',{})))
        self.set_integer(self.ACTOR+0xf8,0 if case.get('null_target',False) else self.REFERENCE)
        self.set_integer(self.ACTOR+0xfc,self.CACHED if 'cached' in case else 0)
        if 'cached' in case:self.cpu.mem_write(self.CACHED+0x18,self.reference(case['cached']))
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,0x105dfb58)
        self.call(0x1016ad70)
        base=0x106f30a8+case.get('action',103)*0xcf8
        for i,entry in enumerate(compiled['states']):
            pointer=base+i*0xa4
            self.cpu.mem_write(pointer,bytes(0xa4))
            self.set_integer(pointer,i+1)
            for key,offset in [('next',0x64),('skip_to',0x70),('end_skip',0x68),('update_type',0x38)]:self.set_integer(pointer+offset,entry[key])
            self.set_float(pointer+0x6c,entry['skip_probability'])
            for key,offset in [('terminable',0x59),('face_end',0x86),('loop',0x58)]:self.cpu.mem_write(pointer+offset,bytes([int(entry[key])]))
        self.cpu.mem_write(base+0xcd0,bytes([int(compiled['looping'])]))
        self.set_integer(base+0xce4,77)
        self.adapters.update({0x10002ac0:self.check,0x103752b0:lambda:self.return_integer(self.TLS),
                              0x1015fcd0:self.end_sound,0x10008860:self.decision,0x100e4180:self.reset_navigation,
                              0x1016b140:self.target_position,0x10065c70:self.face})
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_random,begin=0x1035f7f0,end=0x1035f7f0))

    def end_sound(self):
        voice,event=self.arguments(2)
        if event!=77:raise ValueError('Unexpected original action end sound')
        self.log.append(['end_sound',voice])
        self.return_integer(pop=8)

    def decision(self):
        actor=self.arguments(1)[0]
        reference=self.integer(actor+0xf8)
        self.log.append(['decision',self.integer(actor+0x4c),self.integer(actor+0x6c),self.integer(reference) if reference else None])
        self.return_integer()

    def reset_navigation(self):
        self.log.append(['reset_navigation'])
        self.return_integer()

    def target_position(self):
        pointer=self.arguments(1)[0]
        self.cpu.mem_write(pointer,struct.pack('<3f',*self.case.get('target_position',[160.,122.,6.])))
        self.return_integer(pointer,pop=4)

    def face(self):
        self.log.append(['face',*struct.unpack('<3f',struct.pack('<3I',*self.arguments(3)))])
        self.return_integer(pop=12)

    def ref_snapshot(self,pointer):
        if not pointer:return {}
        identity,entity,x,z,flag=struct.unpack('<IIffI',self.cpu.mem_read(pointer,20))
        return dict(identity=identity,entity=(entity-self.HOUSE)//0x2d8 if entity else -1,position=[x,z],flag=bool(flag&255))

    def advance(self):
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.ACTOR)
        result=self.call(0x1006ae00,[int(self.case.get('first',False))],limit=5000000)
        clip=self.integer(self.ACTOR+0x64)
        return dict(result=bool(result&255),log=self.log,queries=self.queries,random_calls=self.random_calls,random_state=self.integer(self.TLS+0x14),
                    actor=dict(step=self.integer(self.ACTOR+0x4c),entry_done=bool(self.cpu.mem_read(self.ACTOR+0x69,1)[0]),has_channel=self.case.get('has_channel',True),
                               clip=clip if clip<0x80000000 else clip-0x100000000,orientation=self.float(self.ACTOR+0xd4),orientation_rate=self.float(self.ACTOR+0x130),
                               clip_duration=self.float(self.ACTOR+0x60),clip_phase=self.float(self.ACTOR+0x54),clip_time=self.float(self.ACTOR+0x58),
                               action=self.case.get('action',103),phase=self.integer(self.ACTOR+0x6c),voice=self.case.get('voice',0),profile=self.integer(self.ACTOR+0x108),
                               failed=bool(self.cpu.mem_read(self.ACTOR+0x68,1)[0]),native_slot=self.cpu.mem_read(self.ACTOR+0x10,1)[0],gate_slot=self.cpu.mem_read(self.ACTOR+0xe8,1)[0],
                               path_time=self.float(self.ACTOR+0xc0),position=list(struct.unpack('<3f',self.cpu.mem_read(self.ACTOR+0x70,12))),
                               target=self.ref_snapshot(self.integer(self.ACTOR+0xf8)),cached_target=self.ref_snapshot(self.CACHED+0x18) if self.integer(self.ACTOR+0xfc) else {}))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_action_controller.json'))
    args=parser.parse_args()
    controller,source,entry_data=extract(),sequences(),entries()
    oracle=ControllerOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    cases=[dict(name='next'),dict(name='first',first=True,phase=2),dict(name='first_face',first=True),
           dict(name='terminable_failure',failed=True),dict(name='unterminable_failure',failed=True,begin=1),
           dict(name='end_skip',failed=True,begin=1,overrides={'1':dict(end_skip=4)}),
           dict(name='end_skip_zero',failed=True,begin=1,overrides={'1':dict(end_skip=0)}),
           dict(name='next_jump',begin=4),dict(name='no_loop_end',begin=19,looping=False),
           dict(name='loop_restart',begin=19),
           dict(name='entry_failure',clip=347,looping=False,overrides={'1':dict(update_type=200)}),
           dict(name='entry_failure_retry',clip=347,overrides={'1':dict(update_type=200)}),
           dict(name='retry_failure_ignored',clip=347,overrides={'0':dict(update_type=200),'1':dict(update_type=200)}),
           dict(name='end_audio',begin=19,looping=False,house_state=1,voice=1),
           dict(name='phase_two_end',begin=19,looping=False,phase=2,house_state=1),
           dict(name='cached_same',begin=19,looping=False,cached={}),
           dict(name='cached_other',begin=19,looping=False,cached=dict(entity=1,identity=0x01000002)),
           dict(name='cached_same_uid',begin=19,looping=False,cached=dict(entity=1)),
           dict(name='cached_same_position',begin=19,looping=False,target=dict(position=[2.,3.]),cached=dict(entity=1,identity=0x01000002,position=[2.,3.])),
           dict(name='stale_target',begin=19,looping=False,house_identity=0x01000002,cached={}),
           dict(name='no_channel_stale',begin=19,looping=False,house_identity=0x01000002,has_channel=False,cached={}),
           dict(name='invalid_cached',begin=19,looping=False,target=dict(identity=0x1f000000,entity=-1),cached=dict(identity=0x1f000000,entity=-1)),
           dict(name='null_target',begin=19,looping=False,null_target=True,cached={}),
           dict(name='temple_complete',action=114,begin=19,looping=False,completion_state=6),
           dict(name='temple_incomplete',action=114,begin=19,looping=False,completion_state=5),
           dict(name='source_probability',action=127,begin=11,first=True),
           dict(name='source_probabilities',action=131,begin=8,first=True)]
    for action in controller['actions']:
        if action['available']:cases.append(dict(name='source_'+action['name'],action=action['id'],first=True))
    for case in cases:
        compiled=compile_action(source,entry_data,controller,case.get('action',103))
        if 'looping' in case:compiled['looping']=case['looping']
        for index,override in case.get('overrides',{}).items():compiled['states'][int(index)].update(override)
        oracle.configure_controller(case,compiled)
        case['expected']=oracle.advance()
    result={key:controller[key] for key in ['source_sha256','executable_sha256','tables','native_routines']}
    pointer=oracle.SCRATCH+0x9000
    oracle.cpu.mem_write(pointer,bytes(0xa4))
    oracle.cpu.reg_write(oracle.regs.UC_X86_REG_ECX,pointer)
    oracle.call(0x10001c50)
    default=dict(terminable=bool(oracle.cpu.mem_read(pointer+0x59,1)[0]),end_skip=struct.unpack('<i',oracle.cpu.mem_read(pointer+0x68,4))[0],
                 face_end=bool(oracle.cpu.mem_read(pointer+0x86,1)[0]),update_type=oracle.integer(pointer+0x38),loop=bool(oracle.cpu.mem_read(pointer+0x58,1)[0]))
    result.update(cases=cases,default_state=default,scope=__doc__.strip(),adapters=[hex(a) for a in sorted(oracle.adapters)])
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original action controller:',len(cases),'cases')


if __name__=='__main__':main()
