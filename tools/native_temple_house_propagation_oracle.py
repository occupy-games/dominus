"""Compare original house shrine-mask refresh and its actual stat consumer.

The original 100b6e10 callback wrapper, active-site traversal, containment, stored
mask writes and shrine housing-stat getter execute together. Source center and
base rows, geometry refresh and documented string/table services are adapters.
This does not establish geometry refresh internals or source house lifetime.
"""
import copy
import json

from tools.native_scenery_oracle import ROOT
from tools.native_temple_effects_oracle import EffectsOracle,cases as effect_cases,base_words,source_sites
from tools.temple_effects import extract
from tools.reward_dispatch import key


class HousePropagationOracle(EffectsOracle):
    def configure_house_propagation(self,content):
        self.configure_effects(content);self.adapters[0x1003b690]=self.geometry
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def geometry(self):
        assert self.cpu.reg_read(self.regs.UC_X86_REG_ECX)==self.ACTOR+0x74
        self.events.append(['refresh_house_geometry',[],[self.integer(self.ACTOR+0xc+4*i) for i in range(2)]])
        self.return_integer()

    def collect_house(self):
        for i,word in enumerate(self.case['state']['mask']):self.set_integer(self.ACTOR+0xc+4*i,word)
        attached=self.case['state']['reference_attached'];reference=self.GRIDS+0x90000
        self.set_integer(self.ACTOR+0x1cc,reference if attached else 0)
        self.set_integer(reference+0x14,self.case['parameters']['kind'])
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.ACTOR);self.call(0x100b6e10,[0],limit=5000000)

    def run_house(self,case):
        result=self.run_stat(case);current=copy.deepcopy(case['state']);current['mask']=result['mask']
        return dict(state=current,events=copy.deepcopy(self.events),values=result['values'])


def main():
    content=extract();oracle=HousePropagationOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_house_propagation(content)
    examples=[]
    for source in effect_cases(content):
        if source['table']!='House Values':continue
        for attached in [False,True]:
            case=copy.deepcopy(source);case['name']+='_'+str(attached)
            case['state']=dict(position=case['point'],mask=[0xffffffff,0x80000000],reference_attached=attached)
            try:case['expected']=oracle.run_house(case)
            except Exception as error:raise ValueError('Original house propagation '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
            examples.append(case)
    sequences=[]
    for attached in [False,True]:
        sequence=dict(initial=dict(position=[10.,12.,6.],mask=[0,0],reference_attached=attached),steps=[])
        current=copy.deepcopy(sequence['initial'])
        for index in range(16):
            current['position']=[10.+index,12.,6.];sites=source_sites()
            if index%4 in [0,3]:
                for site in sites:site['house_modifiers']=[0,0]
            step=dict(table='House Values',point=current['position'],base=base_words('House Values'),sites=sites,records=content['records'],
                      parameters=dict(special=False,kind=0,model_type=key('AbodeType_1_Rank_1')))
            expected=oracle.run_house(dict(step,state=current));current=copy.deepcopy(expected['state'])
            sequence['steps'].append(dict(step,expected=expected))
        sequences.append(sequence)
    fixture=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],cases=examples,sequences=sequences,
                 native_routines=content['native_routines'],adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_temple_house_propagation.json').write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    print('Original house shrine propagation:',len(examples),'cases,',sum(len(s['steps']) for s in sequences),'steps',flush=True)


if __name__=='__main__':main()
