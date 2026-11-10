"""Execute the original temple terrain/elevation frame and repair work together.

The contiguous 10140d1e..101414d8 block runs, including the real footprint scan,
native powf and currency helpers. Type/terrain queries, spatial registration,
vertical motion, campaign/reward/effect callbacks are explicit source services.
This comparison does not run the earlier affiliation or final removal owner.
"""
import copy
import json
import struct

from tools.native_temple_frame_oracle import FrameOracle,state as frame_state
from tools.native_temple_repair_oracle import TempleOracle,state as repair_state
from tools.native_scenery_oracle import ROOT
from tools.temple_terrain import extract
from tools.temple_repair import extract as repair_content
from tools.reward_dispatch import key


def state(**changes):
    result=repair_state(6)
    result.update(frame_state(phase=6,handle=3));result.update(changes)
    result['start_block']=result['transition_mode']
    return result


class FrameRepairOracle(FrameOracle,TempleOracle):
    END=0x101414d8

    def configure_repair_frame(self,content,repair):
        self.configure_frame(content);self.rules=repair['rules']
        self.adapters.update({0x10245d30:self.source_hook,0x1003ad80:lambda:self.kind('is_dock'),
            0x1003af80:lambda:self.kind('is_pit'),0x1003b1e0:lambda:self.kind('is_ark'),
            0x102545c0:self.composed_sound,0x1006b2e0:self.transition,0x10008860:self.start_action,
            0x1003b840:self.reference_effect,0x10024700:self.context,0x100e0590:self.notice,
            0x10140090:self.visual,0x1035fde0:self.format_unlock,0x1015cd60:self.unlock,
            0x1035f830:lambda:self.return_integer(),0x101b51e0:self.composed_text,0x101b5260:self.composed_hash})
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        for address in [0x10062bb0,0x10062960,0x10141377]:self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe,begin=address,end=address))

    def event(self,name,args=()):self.record(name,args)

    def composed_sound(self):
        args=list(self.arguments(5))
        assert args[1]==self.site+0x278
        caller=self.integer(self.cpu.reg_read(self.regs.UC_X86_REG_ESP))
        if caller==0x10141339:self.record('sound',[args[0],[self.float(self.site+offset) for offset in [0x278,0x27c,0x280]],*args[2:]])
        else:self.record('sound',[args[0],*args[2:]])
        self.return_integer()

    def composed_text(self):
        pointer=self.arguments(1)[0]
        self.unlock_name=bytes(self.cpu.mem_read(pointer,80)).split(b'\0')[0].decode()
        self.return_integer(pop=4)

    def composed_hash(self):self.return_integer(key('boat') if self.unlock_name=='boat' else 0x1234)

    def prepare_extra(self):
        s=self.case['state']
        self.set_integer(0x10f29ba0,self.POOL)
        for name,offset in [('source_id',0x10),('food_cost',0x408),('ore_cost',0x40c),('start_block',0x3c4),('reward_pending',0x238),('notice_data',0x130)]:self.set_integer(self.site+offset,s[name])
        self.set_integer(self.site+0x234,123 if s['reward'] else 0)
        self.cpu.mem_write(self.site+0x2c0,bytes([int(s['reward_ready'])]))
        self.set_integer(self.site+4,self.SCRATCH+0x3000);self.set_integer(self.site+8,self.SCRATCH+0x3000+len(s['references'])*4)
        for index,value in enumerate(s['references']):self.set_integer(self.SCRATCH+0x3000+index*4,value)
        for name,address in [('food',0x1096c5e0),('ore',0x1096c628)]:self.cpu.mem_write(address,struct.pack('<q',int(self.case.get('currency',{}).get(name,10))))
        self.set_float(0x105d4c40,self.case.get('exponent',self.rules['exponent']))
        totals=self.case.get('totals',dict(workers=1,contributors=1,skill_sum=1.))
        index=s['handle']*4
        self.set_integer(0x10f9e8f0+index,totals['workers']);self.set_integer(0x10f9eb48+index,totals['contributors']);self.set_float(0x10f9eda0+index,totals['skill_sum'])
        self.set_integer(0x10d9b664,self.case.get('mode',0));self.set_integer(0x10d9b670,self.case.get('player',0))
        self.set_integer(self.SCRATCH+0x6000,12345)
        followers=self.case.get('followers',[])
        self.set_integer(0x10fcd450,self.GRIDS+0x20000);self.cpu.mem_write(0x10fcd45a,struct.pack('<H',0 if followers else 0xffff))
        for index,follower in enumerate(followers):
            pointer=self.GRIDS+0x20000+index*0x13c;self.cpu.mem_write(pointer,bytes(0x13c))
            self.cpu.mem_write(pointer,struct.pack('<H',index+1 if index+1<len(followers) else 0xffff))
            target=self.GRIDS+0x30000+index*0x40;self.set_integer(pointer+0x100,target)
            self.set_integer(target+0x20,self.site if follower.get('targets_site',False) else self.site+0x43c)

    def snapshot(self):
        result=FrameOracle.snapshot(self);repair=TempleOracle.snapshot(self)
        for name in ['food_cost','ore_cost','reward','reward_pending','reward_ready','references']:result[name]=repair[name]
        return result


def cases():
    examples=[]
    for phase in [0,1,5,6,7,8]:
        for raw in [19,21]:
            for forced in [False,True]:
                for workers in [0,1,2]:
                    examples.append(dict(name=f'work_{phase}_{raw}_{forced}_{workers}',state=state(phase=phase,forced=forced,progress=59.,required=60.),ground=dict(default=raw),delta=.25,totals=dict(workers=workers,contributors=workers,skill_sum=float(workers))))
    for kind in ['ordinary','dock','pit','settlement','ark']:
        for mode in [0,1]:
            for reward in [0,'Pack_PrimitiveB']:
                case=dict(name=f'complete_{kind}_{mode}_{reward}',state=state(progress=59.,required=60.,reward=reward),ground=dict(default=19),delta=.25,mode=mode,is_settlement=kind=='settlement',totals=dict(workers=2,contributors=2,skill_sum=3.))
                case['is_'+kind]=True
                case['followers']=[dict(id=10,targets_site=True),dict(id=11,targets_site=False),dict(id=12,targets_site=True)]
                examples.append(case)
    for before in [0.,59.,60.]:
        examples.append(dict(name=f'passive_only_{before}',state=state(progress=before),ground=dict(default=19),delta=.25,totals=dict(workers=0,contributors=0,skill_sum=0.)))
        examples.append(dict(name=f'no_passive_{before}',state=state(progress=before,transition_mode=0),ground=dict(default=19),delta=.25,totals=dict(workers=0,contributors=0,skill_sum=0.)))
    examples.append(dict(name='completion_callback_clears_reward',state=state(progress=59.),ground=dict(default=19),delta=.25,clear_reward_during_visual=True))
    return examples


def main():
    content=extract();repair=repair_content();oracle=FrameRepairOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_repair_frame(content,repair)
    examples=cases()
    for case in examples:
        try:case['expected']=oracle.run_frame(case)
        except Exception as error:raise ValueError('Original composed frame '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    sequences=[]
    for required in [4.,60.]:
        sequence=dict(initial=state(progress=0.,required=required),steps=[]);current=copy.deepcopy(sequence['initial'])
        for index in range(24):
            step=dict(delta=.25,ground=dict(default=21 if 3<=index<6 else 19),totals=dict(workers=2,contributors=2,skill_sum=3.),is_settlement=True)
            expected=oracle.run_frame(dict(step,state=current));current=copy.deepcopy(expected['state'])
            sequence['steps'].append(dict(step,expected=expected))
        sequences.append(sequence)
    fixture=dict(executable_sha256=content['executable_sha256'],cases=examples,sequences=sequences,
                 native_routines=dict(content['native_routines'],**repair['native_routines']),adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_temple_frame_repair.json').write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    print('Original composed temple frame and repair:',len(examples),'cases,',sum(len(s['steps']) for s in sequences),'steps',flush=True)


if __name__=='__main__':main()
