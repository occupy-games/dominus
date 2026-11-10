"""Execute full original era-cache refresh and original unlock-set queries.

Only string formatting/allocation and period-change delivery are adapted. The
original control flow, recursive refresh, hashes, membership walks and cache
writes execute. No source wall clock, I/O, application entrypoint or OS executes.
"""
import copy
import json
import random

from tools.era_progression import extract
from tools.reward_dispatch import key
from tools.native_scenery_oracle import Oracle,ROOT


def state(valid=False,period=0,era=0):return dict(cache_valid=valid,period=period,era=era)


class EraOracle(Oracle):
    GLOBAL=0x10f17c0c
    LOCAL=Oracle.SCRATCH+0x8000

    def configure_era(self):
        self.adapters={0x10001020:self.allocate,0x103454b0:self.allocate,0x103571c0:lambda:self.return_integer(),
                       0x1007f4a0:self.format,0x100128c0:self.period_changed,
                       0x1035f830:lambda:self.return_integer(self.cpu.reg_read(self.regs.UC_X86_REG_EAX))}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.query,begin=0x1015c1e0,end=0x1015c1e0))

    def allocate(self):
        self.return_integer(self.alloc(self.arguments(1)[0]))
    def alloc(self,count):
        pointer=self.heap;self.heap+=(count+15)&~15
        if self.heap>self.POOL+0x1000000:raise ValueError('Era fixture heap exhausted')
        self.cpu.mem_write(pointer,bytes((count+15)&~15))
        return pointer
    def string(self,pointer):return bytes(self.cpu.mem_read(pointer,256)).split(b'\0')[0].decode()
    def format(self):
        output,template,end,capacity,index=self.arguments(5)
        template=self.string(template)
        if template not in ['ERA_MASTER_%d','ERA_STICKER_%d']:raise ValueError('Unexpected era format')
        text=template%index
        pointer=self.alloc(len(text)+1)
        self.cpu.mem_write(pointer,text.encode()+b'\0')
        for offset,value in [(0,pointer),(4,pointer+len(text)),(8,pointer+len(text)+1)]:self.set_integer(output+offset,value)
        self.return_integer(output)
    def query(self,cpu,address,size,user):self.events.append(['unlocked',[self.string(self.arguments(1)[0])]])
    def period_changed(self):
        self.events.append(['period_changed',self.arguments(1)])
        if self.step.get('invalidate_on_notification',False):self.cpu.mem_write(self.GLOBAL,b'\0')
        self.return_integer()

    def load_state(self,pointer,value):
        self.cpu.mem_write(pointer,bytes(12))
        self.cpu.mem_write(pointer,bytes([int(value['cache_valid'])]))
        self.set_integer(pointer+4,value['period']);self.set_integer(pointer+8,value['era'])
    def read_state(self,pointer):return state(bool(self.cpu.mem_read(pointer,1)[0]),self.integer(pointer+4),self.integer(pointer+8))
    def unlocks(self,names):
        self.cpu.mem_write(0x10cd9760,bytes(1024*4))
        for i,identity in enumerate(sorted(set(key(name) for name in names))):
            bucket=0x10cd9760+(identity&1023)*4
            pointer=self.GRIDS+i*8
            self.set_integer(pointer,identity)
            self.set_integer(pointer+4,self.integer(bucket))
            self.set_integer(bucket,pointer)
    def run_case(self,case):
        self.heap=self.POOL+0x10000
        self.load_state(self.GLOBAL,case.get('global',case['state']))
        self.load_state(self.LOCAL,case['state'])
        self.unlocks(case.get('unlocks',[]))
        result=[]
        for step in case['steps']:
            self.step=step;self.events=[]
            if 'unlocks' in step:self.unlocks(step['unlocks'])
            pointer=self.GLOBAL if not case.get('local',False) else self.LOCAL
            if step.get('invalidate',False):self.cpu.mem_write(pointer,b'\0')
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,pointer)
            action=step.get('action','era')
            value=self.call(0x100f62b0 if action=='era' else 0x100f5c30,limit=500000)
            result.append(dict(value=value if action=='era' else None,state=self.read_state(pointer),global_state=self.read_state(self.GLOBAL),events=copy.deepcopy(self.events)))
        return result


def cases():
    examples=[]
    def add(name,cache=None,unlocks=None,steps=None,**extra):
        examples.append(dict(name=name,state=cache or state(),unlocks=unlocks or [],steps=steps or [{},{},dict(invalidate=True),{}],**extra))
    add('none')
    add('already_valid',state(True,7,9),['ERA_MASTER_2','ERA_STICKER_2'])
    add('cached_unsigned',state(True,0xffffffff,0xffffffff))
    for period in range(13):
        for era in range(13):add(f'levels_{period}_{era}',unlocks=['ERA_MASTER_'+str(period),'ERA_STICKER_'+str(era)])
    add('higher_wins',unlocks=['ERA_MASTER_'+str(i) for i in range(13)]+['ERA_STICKER_'+str(i) for i in range(13)])
    add('out_of_range',unlocks=['ERA_MASTER_13','ERA_STICKER_13','ERA_MASTER_99','ERA_STICKER_99'])
    add('decrease',state(False,8,9),['ERA_MASTER_2','ERA_STICKER_1'])
    add('notification_invalidation',unlocks=['ERA_MASTER_2','ERA_STICKER_3'],steps=[dict(invalidate_on_notification=True),{},{}])
    add('changes_require_invalidation',unlocks=['ERA_STICKER_1'],steps=[{},dict(unlocks=['ERA_STICKER_4']),dict(invalidate=True),{}])
    add('local_reenters_dirty_global',state(False,1,4),['ERA_MASTER_3','ERA_STICKER_2'],local=True,**{'global':state()})
    add('local_uses_valid_global_period',state(False,0,0),['ERA_MASTER_3','ERA_STICKER_2'],local=True,**{'global':state(True,8,9)})
    rng=random.Random(0xe4acac4e)
    for i in range(80):
        names=[f'ERA_{kind}_{number}' for kind in ['MASTER','STICKER'] for number in range(15) if rng.randrange(4)==0]
        add('random_'+str(i),state(bool(i&1),rng.randrange(15),rng.randrange(15)),names)
    return examples


def main():
    content=extract();oracle=EraOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_era()
    examples=cases()
    for case in examples:
        try:case['states']=oracle.run_case(case)
        except Exception as error:raise ValueError('Original era '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    result=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],native_routines=content['native_routines'],
                adapters=[hex(a) for a in sorted(oracle.adapters)],cases=examples,scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_era.json').write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Original era cache:',len(examples),'cases,',sum(len(c['steps']) for c in examples),'queries')


if __name__=='__main__':main()
