"""Execute original upgrade-mask refresh inside the complete compared shrine frame.

The actual modifier loop, popcounts and unlock hash lookup run before original
timed affiliation, footprint/burial, elevation and repair/completion. Only source
table parsing, spatial invalidation and the frame's documented services remain
adapters. No original entrypoint or operating-system/device code is run.
"""
import copy
import json

from tools.native_temple_lifecycle_oracle import LifecycleOracle,cases as lifecycle_cases,state
from tools.native_temple_modifiers_oracle import load_tables,write_masks,read_masks
from tools.native_temple_membership_oracle import site
from tools.native_scenery_oracle import ROOT
from tools.temple_modifiers import extract as modifiers_content
from tools.temple_membership import extract as membership_content
from tools.temple_terrain import extract
from tools.temple_repair import extract as repair_content
from tools.reward_dispatch import key


class ModifiedLifecycleOracle(LifecycleOracle):
    def configure_modified(self,content,repair):
        self.configure_lifecycle(content,repair)
        del self.adapters[0x1013dd90]
        self.adapters[0x1012c970]=self.invalidate_modifiers
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        for address in [0x10062bb0,0x10062960,0x10141377]:self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe,begin=address,end=address))
        for address in [0x1013dd90,0x1015c130]:self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_modifiers,begin=address,end=address))

    def record(self,name,args=()):
        super().record(name,args);self.events[-1].append(read_masks(self))

    def observe_modifiers(self,cpu,address,size,user):
        self.record('unlocked',self.arguments(1)) if address==0x1015c130 else self.record('refresh_modifiers')

    def invalidate_modifiers(self):
        values=[v-0x100000000 if v>=0x80000000 else v for v in self.arguments(2)]
        self.record('invalidate_modifiers_at',values);self.return_integer()

    def prepare_extra(self):
        super().prepare_extra();write_masks(self,self.case['state']);load_tables(self,self.case['records'],self.case['unlocked'])

    def snapshot(self):
        result=super().snapshot();result.update(read_masks(self));return result


def main():
    terrain=extract();repair=repair_content();membership=membership_content();modifiers=modifiers_content()
    oracle=ModifiedLifecycleOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_modified(terrain,repair)
    types=[*dict.fromkeys(r['type'] for r in modifiers['records']),key('Settlement_Builder')]
    all_unlocks=list(dict.fromkeys(r['unlock'] for r in modifiers['records']))
    examples=[]
    for index,case in enumerate(lifecycle_cases()):
        if 'modifiers_state' in case:continue
        current=case['state'];current.update(generic_type=types[index%4],is_settlement=index%4==3,
                                           follower_modifiers=[1,0] if index%3==0 else [0,0],house_modifiers=[0,0])
        case.update(is_settlement=current['is_settlement'],records=modifiers['records'],unlocked=all_unlocks if index%2 else [all_unlocks[0]])
        try:case['expected']=oracle.run_frame(case)
        except Exception as error:raise ValueError('Native modified lifecycle '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
        examples.append(case)
    sequences=[]
    for kind in types:
        sequence=dict(initial=state(generic_type=kind,is_settlement=kind==types[-1],progress=0.,required=4.,follower_modifiers=[0,0],house_modifiers=[0,0]),steps=[])
        current=copy.deepcopy(sequence['initial'])
        for index in range(32):
            step=dict(sites=[site(4,settlement_id=2,is_settlement=True)],times=[float(index)],word=16383,delta=.25,
                      records=modifiers['records'],unlocked=all_unlocks if index%6 in [1,2,3] else [],
                      ground=dict(default=21 if 3<=index<6 or 18<=index<22 else 19),totals=dict(workers=2,contributors=2,skill_sum=3.))
            expected=oracle.run_frame(dict(step,state=current));current=copy.deepcopy(expected['state'])
            sequence['steps'].append(dict(step,expected=expected))
        sequences.append(sequence)
    fixture=dict(executable_sha256=terrain['executable_sha256'],source_sha256=membership['source_sha256'],cases=examples,sequences=sequences,
                 native_routines=dict(terrain['native_routines'],**repair['native_routines'],**membership['native_routines'],**modifiers['native_routines']),
                 adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_temple_modified_lifecycle.json').write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    print('Original modified temple lifecycle:',len(examples),'cases,',sum(len(s['steps']) for s in sequences),'steps',flush=True)


if __name__=='__main__':main()
