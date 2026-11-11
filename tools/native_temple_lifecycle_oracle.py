"""Compare contiguous original temple affiliation, terrain and repair instructions.

The original 10140c0f..101414d8 block executes with its actual incoming x87
state. Containment, active-list traversal, footprint scan, decay, height and
repair/completion run together. Modifier refresh, clock/RNG, type records,
terrain, spatial/motion and external completion services are explicit adapters.
No original entrypoint, operating-system import or device is executed.
"""
import copy
import json
import random
import struct

from tools.native_temple_frame_repair_oracle import FrameRepairOracle,state as frame_state,cases as frame_cases
from tools.native_temple_membership_oracle import MembershipOracle,site
from tools.native_temple_terrain_oracle import f32
from tools.native_scenery_oracle import ROOT
from tools.temple_membership import extract as membership_content
from tools.temple_terrain import extract
from tools.temple_repair import extract as repair_content
from tools.reward_dispatch import key


def state(**changes):
    result=frame_state();result.update(settlement_id=-1,is_settlement=False,radius=12.,affiliation_due=0.)
    result.update(changes)
    for field in ['radius','affiliation_due']:result[field]=f32(result[field])
    result['start_block']=result['transition_mode']
    return result


class LifecycleOracle(FrameRepairOracle,MembershipOracle):
    START=0x10140c0f

    def configure_lifecycle(self,content,repair):
        self.configure_repair_frame(content,repair)
        self.adapters.update({0x100400b0:self.settlement,0x1003fee0:self.lookup,
                              0x1013dd90:self.modifiers,0x10179810:self.clock,0x1035f7f0:self.random_word})
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        for address in [0x10062bb0,0x10062960,0x10141377]:self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe,begin=address,end=address))

    def record(self,name,args=()):
        super().record(name,args)
        owner=self.integer(self.site+0x2b4)
        self.events[-1].extend([owner-0x100000000 if owner>=0x80000000 else owner,self.float(self.site+0x378)])

    def settlement(self):
        caller=self.integer(self.cpu.reg_read(self.regs.UC_X86_REG_ESP))
        if 0x10140d1e<=caller<self.END:self.record('is_settlement')
        MembershipOracle.settlement(self)

    def lookup(self):
        pointer=self.arguments(1)[0]-0x30c
        row=self.SCRATCH+0x8000
        caller=self.integer(self.cpu.reg_read(self.regs.UC_X86_REG_ESP))
        if 0x101410c8<=caller<0x10141204:self.record('is_boat')
        self.set_integer(row+4,key('boat') if pointer==self.site and self.case.get('boat',False) else 123)
        self.set_float(row+0x10,self.records[pointer]['radius'])
        self.return_integer(row,pop=4)

    def modifiers(self):
        MembershipOracle.modifiers(self)
        for field,value in self.case.get('modifiers_state',{}).items():
            if field in self.FLOATS:self.set_float(self.site+self.FLOATS[field],value)
            elif field in self.FIELDS:self.set_integer(self.site+self.FIELDS[field],value)
            else:raise ValueError('Unknown modifier slot '+field)

    def prepare_extra(self):
        super().prepare_extra()
        current=self.case['state'];self.clock_calls=0;self.random_calls=0;self.records={self.site:copy.deepcopy(current)}
        sites=self.case.get('sites',[])
        self.cpu.mem_write(0x10f29baa,struct.pack('<H',sites[0]['handle'] if sites else 0xffff))
        for index,data in enumerate(sites):
            pointer=self.POOL+data['handle']*0x43c
            if pointer!=self.site:self.write_site(pointer,data)
            self.cpu.mem_write(pointer,struct.pack('<H',sites[index+1]['handle'] if index+1<len(sites) else 0xffff))
        self.set_integer(self.site+0x2b4,current['settlement_id'])
        self.set_float(self.site+0x378,current['affiliation_due'])
        for index,(identity,data) in enumerate(self.case.get('owners',{}).items()):
            pointer=self.GRIDS+0x100000+index*0x43c
            self.write_site(pointer,data);self.set_integer(0x10bc9878+int(identity)*384,pointer)

    def snapshot(self):
        result=super().snapshot();owner=self.integer(self.site+0x2b4)
        result['settlement_id']=owner-0x100000000 if owner>=0x80000000 else owner
        result['affiliation_due']=self.float(self.site+0x378)
        return result

    def run_frame(self,case):
        result=super().run_frame(case)
        result.update(clock_calls=self.clock_calls,random_calls=self.random_calls,refreshed=bool(self.random_calls))
        return result


def cases():
    first=site(4,settlement_id=2,is_settlement=True)
    second=site(7,settlement_id=5,is_settlement=True,x=11.)
    examples=[]
    for case in frame_cases():
        current=state(**case['state'],is_settlement=case.get('is_settlement',False))
        examples.append(dict(case,state=current,sites=[first,second],times=[1.,1.25],word=16383))
    for due in [-1.,0.,1.]:
        for owner in [-1,2]:
            for settlement in [False,True]:
                for forced in [False,True]:
                    examples.append(dict(name=f'timed_{due}_{owner}_{settlement}_{forced}',
                        state=state(phase=6,affiliation_due=due,settlement_id=owner,is_settlement=settlement,forced=forced),
                        sites=[first,second],times=[0.,.25],word=32767,ground=dict(default=19),delta=.25))
    for ordered in [[first,second],[second,first],[]]:
        examples.append(dict(name='order_'+','.join(str(s['handle']) for s in ordered),state=state(),sites=ordered,times=[1.,2.],word=0,ground=dict(default=19)))
    for due in [0.,2.]:
        examples.append(dict(name=f'modifier_{due}',state=state(phase=6,progress=0.),sites=[first],times=[1.],word=0,
                             modifiers_due=due,modifiers_state=dict(progress=59.5,height_ceiling=5.5),ground=dict(default=19),delta=.25))
    rng=random.Random(0x10140c0f)
    for index in range(48):
        now=f32(rng.choice([0.,100.,10000000.])+rng.random()*10)
        examples.append(dict(name=f'arithmetic_{index}',state=state(phase=rng.choice([5,6,7,8]),progress=f32(rng.random()*60),
            affiliation_due=f32(now+rng.choice([-1,0,1])),height=f32(5+rng.random()*2),forced=bool(index%2)),
            sites=[second,first] if index%3 else [],times=[now,f32(now+rng.random())],word=rng.randrange(32768),
            delta=f32(rng.random()),ground=dict(default=rng.choice([19,21])),totals=dict(workers=2,contributors=2,skill_sum=3.)))
    return examples


def main():
    terrain=extract();repair=repair_content();membership=membership_content()
    oracle=LifecycleOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_lifecycle(terrain,repair)
    examples=cases()
    for case in examples:
        try:case['expected']=oracle.run_frame(case)
        except Exception as error:raise ValueError('Native lifecycle '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    sequences=[]
    for initial_owner in [-1,2]:
        for settlement in [False,True]:
            sequence=dict(initial=state(settlement_id=initial_owner,is_settlement=settlement,progress=0.,required=4.),steps=[])
            current=copy.deepcopy(sequence['initial'])
            for index in range(32):
                step=dict(sites=[site(4,settlement_id=2,is_settlement=True)],times=[float(index)],word=16383,delta=.25,
                          ground=dict(default=21 if 3<=index<6 or 18<=index<22 else 19),totals=dict(workers=2,contributors=2,skill_sum=3.))
                expected=oracle.run_frame(dict(step,state=current));current=copy.deepcopy(expected['state'])
                sequence['steps'].append(dict(step,expected=expected))
            sequences.append(sequence)
    fixture=dict(executable_sha256=terrain['executable_sha256'],source_sha256=membership['source_sha256'],cases=examples,sequences=sequences,
                 native_routines=dict(terrain['native_routines'],**repair['native_routines'],**membership['native_routines']),
                 adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_temple_lifecycle.json').write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    print('Original temple lifecycle:',len(examples),'cases,',sum(len(s['steps']) for s in sequences),'steps',flush=True)


if __name__=='__main__':main()
