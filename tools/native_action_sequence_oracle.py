"""Execute native state selection and its actual seeded CRT random generator.

Only state validity and the CRT's thread-record lookup are adapted. Source
actions/controls are injected explicitly; state entry, movement and jobs are
outside this capture. No original application entrypoint or host TLS executes.
"""
import argparse
import json
import struct

from tools.action_sequences import extract
from tools.native_scenery_oracle import Oracle, ROOT


class SequenceOracle(Oracle):
    ACTOR=0x31800000
    TLS=0x31801000
    BASE=0x106f30a8

    def configure_sequence(self,case,states):
        for handle in self.handles:self.cpu.hook_del(handle)
        self.case=case
        self.queries=[]
        self.random_calls=0
        self.cpu.mem_write(self.ACTOR,bytes(0x200))
        self.set_integer(self.ACTOR+0x7c,0)
        self.set_integer(self.TLS+0x14,case.get('seed',1))
        for i,entry in enumerate(states):
            pointer=self.BASE+i*0xa4
            self.cpu.mem_write(pointer,bytes(0xa4))
            self.set_integer(pointer,i+1) # A by-value marker, not a rule input.
            for key,offset in [('next',0x64),('skip_to',0x70)]:self.set_integer(pointer+offset,entry[key])
            self.set_float(pointer+0x6c,entry['skip_probability'])
        self.adapters={0x10002ac0:self.check,0x103752b0:lambda:self.return_integer(self.TLS)}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_random,begin=0x1035f7f0,end=0x1035f7f0))

    def observe_random(self,cpu,address,size,user):self.random_calls+=1

    def check(self):
        pointer=self.cpu.reg_read(self.regs.UC_X86_REG_ECX)
        index=self.integer(pointer)-1
        self.queries.append(index)
        actor,lost=self.arguments(2)
        if actor!=self.ACTOR:raise ValueError('Unexpected native state-check owner')
        if index in self.case.get('lose_at',[]):self.cpu.mem_write(lost,b'\x01')
        for key,value in self.case.get('mutate',{}).get(str(index),{}).items():
            self.set_integer(pointer+dict(next=0x64,skip_to=0x70)[key],value)
        self.return_integer(int(self.case.get('checks',{}).get(str(index),True)),pop=8)

    def choose_state(self):
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.ACTOR)
        index=self.call(0x10065a10,[self.case.get('begin',0)],limit=2000000)
        return dict(index=index,queries=self.queries,random_calls=self.random_calls,random_state=self.integer(self.TLS+0x14))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_action_sequence.json'))
    args=parser.parse_args()
    content=extract()
    oracle=SequenceOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    cases=[dict(name='first'),dict(name='skip_invalid',checks={'0':False}),
           dict(name='all_invalid',checks={str(i):False for i in range(20)}),
           dict(name='lost_valid',lose_at=[0]),dict(name='lost_persists',checks={'0':False},lose_at=[0]),
           dict(name='finished',begin=20),dict(name='outside',begin=99),
           dict(name='jump',checks={'0':False},overrides={'0':dict(skip_to=5)}),
           dict(name='loop_guard',checks={'0':False},overrides={'0':dict(skip_to=0)}),
           dict(name='probability_zero',overrides={'0':dict(skip_probability=0.)}),
           dict(name='probability_negative',overrides={'0':dict(skip_probability=-1.)}),
           dict(name='probability_one',overrides={'0':dict(skip_probability=1.)}),
           dict(name='probability_equal',seed=((0x7fff0000-2531011)*pow(214013,-1,1<<32))%(1<<32),overrides={'0':dict(skip_probability=1.)}),
           dict(name='probability_above_one',overrides={'0':dict(skip_probability=2.)}),
           dict(name='probability_loop',overrides={'0':dict(skip_probability=2.,skip_to=0)}),
           dict(name='zero_seed',seed=0,overrides={'0':dict(skip_probability=.5)}),
           dict(name='unsigned_seed',seed=0xffffffff,overrides={'0':dict(skip_probability=.5)}),
           dict(name='mixed',seed=123456,checks={'1':False,'3':False},overrides={str(i):dict(skip_probability=.3) for i in range(6)}),
           dict(name='by_value_check',checks={'0':False},mutate={'0':dict(skip_to=5)})]
    # Compare every available source state's normal entry, not just builders.
    for action in content['actions']:
        if any(not row['available'] for row in action['states']):continue
        for entry in action['states']:
            cases.append(dict(name=action['name']+'_'+str(entry['index']),action=action['id'],begin=entry['index']))
    definitions={action['id']:action for action in content['actions']}
    for case in cases:
        states=[dict(content['default_state']) for _ in range(content['rules']['capacity'])]
        if 'action' in case:
            for row in definitions[case['action']]['states']:states[row['index']]=row
        for index,override in case.get('overrides',{}).items():states[int(index)]=dict(states[int(index)],**override)
        oracle.configure_sequence(case,states)
        case['expected']=oracle.choose_state()
    # The actual default constructor independently establishes unspecified slots.
    oracle.cpu.reg_write(oracle.regs.UC_X86_REG_ECX,oracle.ACTOR)
    oracle.call(0x10001c50)
    default=dict(next=struct.unpack('<i',oracle.cpu.mem_read(oracle.ACTOR+0x64,4))[0],
                 skip_to=struct.unpack('<i',oracle.cpu.mem_read(oracle.ACTOR+0x70,4))[0],
                 skip_probability=oracle.float(oracle.ACTOR+0x6c))
    result={key:content[key] for key in ['source_sha256','executable_sha256','tables','native_routines']}
    result.update(cases=cases,default=default,scope=__doc__.strip(),adapters=[hex(a) for a in sorted(oracle.adapters)])
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original action sequence:',len(cases),'cases')


if __name__=='__main__':main()
