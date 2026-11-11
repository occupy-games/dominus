"""Execute original house shrine refresh, actual foundation scan and stat getter.

Original 100b6e10 calls original 1003b690 without an intervening adapter. The
mask, reference gate, scan bounds, overlay/fallback queries and foundation count
run together before the original housing-stat consumer. Source table/base rows,
terrain services and documented string/center services remain adapters.
"""
import copy
import json

from tools.native_scenery_oracle import ROOT
from tools.native_temple_house_propagation_oracle import HousePropagationOracle
from tools.native_building_foundation_oracle import FoundationOracle
from tools.temple_effects import extract as effect_content
from tools.building_foundation import extract
from tools.native_temple_effects_oracle import base_words,source_sites
from tools.reward_dispatch import key


class HouseFoundationOracle(HousePropagationOracle,FoundationOracle):
    def configure_composed(self,content):
        self.configure_house_propagation(content)
        del self.adapters[0x1003b690]
        self.adapters.update({0x100d0e90:self.overlay_owner,0x1015df40:self.overlay,0x101450b0:self.ground})
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_bounds,begin=0x1003b75c,end=0x1003b75c))

    def foundation_event(self,name,args=()):
        self.events.append([name,list(args),[self.integer(self.ACTOR+0xc+4*i) for i in range(2)],self.integer(self.body+0x80)])

    def collect_house(self):
        self.body=self.ACTOR+0x74;self.write_foundation(self.case['state'])
        super().collect_house()

    def run_house(self,case):
        self.region=[]
        result=super().run_house(case)
        result['state']['uneven_count']=self.integer(self.body+0x80);result['bounds']=self.region
        return result


def main():
    content=extract();effects=effect_content()
    original=json.loads((ROOT/'game/tests/fixtures/source_temple_house_propagation.json').read_text())
    if original['executable_sha256']!=content['executable_sha256']:raise ValueError('Mismatched original house fixture')
    oracle=HouseFoundationOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_composed(effects)
    examples=[]
    for index,source in enumerate(original['cases']):
        case={key:copy.deepcopy(value) for key,value in source.items() if key!='expected'}
        case['state'].update(anchor_step=20,nav_size=index%4,uneven_count=0x80000000)
        case.update(overlay_available=bool(index%3),overlay=dict(default=dict(found=index%4!=0,height=20. if index%5==0 else 19.)),ground=dict(default=20. if index%2 else 21.))
        try:case['expected']=oracle.run_house(case)
        except Exception as error:raise ValueError('Original house foundation '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
        examples.append(case)
    sequences=[]
    for attached in [False,True]:
        sequence=dict(initial=dict(position=[10.,12.,6.],mask=[0,0],reference_attached=attached,anchor_step=20,nav_size=2,uneven_count=999),steps=[])
        current=copy.deepcopy(sequence['initial'])
        for index in range(24):
            current['position']=[10.+index,12.5,6.];sites=source_sites()
            if index%4 in [0,3]:
                for site in sites:site['house_modifiers']=[0,0]
            step=dict(table='House Values',point=current['position'],base=base_words('House Values'),sites=sites,records=effects['records'],
                      parameters=dict(special=False,kind=0,model_type=key('AbodeType_1_Rank_1')),overlay_available=True,
                      overlay=dict(default=dict(found=index%4!=0,height=20. if index%4 in [1,2] else 21.)),ground=dict(default=20. if index%6 in [0,1] else 19.))
            expected=oracle.run_house(dict(step,state=current));current=copy.deepcopy(expected['state'])
            sequence['steps'].append(dict(step,expected=expected))
        sequences.append(sequence)
    fixture=dict(executable_sha256=content['executable_sha256'],source_sha256=effects['source_sha256'],cases=examples,sequences=sequences,
                 native_routines=dict(effects['native_routines'],**content['native_routines']),adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_temple_house_foundation.json').write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    print('Original house shrine/foundation composition:',len(examples),'cases,',sum(len(s['steps']) for s in sequences),'steps',flush=True)


if __name__=='__main__':main()
