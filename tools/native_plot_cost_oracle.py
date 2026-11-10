"""Execute original plot food cost and both affordability predicates.

Resolved source rows, unlock membership, settlement lookup, the original
per-tick counted-house total and signed 64-bit currencies are explicit inputs.
The cost, row selector, height/biome conversion and affordability arithmetic run
unchanged. This does not establish settlement coverage or the full economy.
"""
import argparse
import json
import struct

from tools.house_selection import extract
from tools.native_house_selection_oracle import SelectionOracle
from tools.native_scenery_oracle import ROOT
from tools.plot_cost import extract as costs


class CostOracle(SelectionOracle):
    def configure_cost(self):
        self.selection=extract()
        self.configure_selection(self.selection)
        self.content=costs()
        self.set_float(0x105b2d08,25.)
        self.set_float(0x105b2d0c,36.)
        self.adapters.update({0x10124d70:self.settlement,0x10124660:self.food_gate,
                              0x10062960:lambda:self.currency('food'),0x10062bb0:lambda:self.currency('ore')})
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def settlement(self):
        self.queries.append(list(struct.unpack('<3f',struct.pack('<3I',*self.arguments(3)))))
        self.return_integer(self.case.get('settlement',0xffffffff))

    def food_gate(self):
        self.return_integer(int(self.case.get('food_enabled',True)))

    def currency(self,name):
        value=self.case.get(name,100)
        self.cpu.reg_write(self.regs.UC_X86_REG_EDX,(value>>32)&0xffffffff)
        self.return_integer(value&0xffffffff)

    def observe(self,case):
        self.case=case
        self.profile(dict(unlocks=case.get('unlocks',['PlotsAppear']),biome_locked=case.get('biome_locked',True)))
        for row in self.content['costs']:self.set_float(0x10fc241c+row['index']*0x130+0x108,row['food'])
        for key,value in case.get('cost_override',{}).items():self.set_float(0x10fc241c+int(key)*0x130+0x108,value)
        self.set_integer(0x107d1b44,case.get('counted_houses',1))
        for key,pointer in [('biome1Index',0x1060fd2c),('biome2Index',0x1060fd30),('biome3Index',0x1060fd34)]:
            self.set_float(pointer,case.get('configuration',{}).get(key,self.selection['configuration'][key]))
        plot=dict(x=158.,z=120.,size=4,height=6.)
        plot.update(case.get('plot',{}))
        self.cpu.mem_write(self.POOL,bytes(0x74))
        self.set_integer(self.POOL+4,plot['size'])
        for key,offset in [('x',8),('z',12),('height',16)]:self.set_float(self.POOL+offset,plot[key])
        self.queries=[]
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.POOL)
        amount=self.call(0x10235bd0,[case.get('mode',1)],floating=True)
        queries=list(self.queries)
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.POOL)
        allowed=self.call(0x10235c90,[case.get('mode',1)])
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.POOL)
        both=self.call(0x10235cf0)
        return dict(amount=amount,allowed=bool(allowed),both=bool(both),queries=queries)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_plot_cost.json'))
    args=parser.parse_args()
    oracle=CostOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_cost()
    cases=[dict(name='first'),dict(name='no_counted_houses',counted_houses=0),
           dict(name='disabled',food_enabled=False),dict(name='settled',settlement=7),
           dict(name='locked',unlocks=[]),dict(name='short',food=2),dict(name='exact',food=3),
           dict(name='negative_food',food=-1),dict(name='negative_ore',ore=-1),dict(name='zero_ore',ore=0),
           dict(name='int64',food=(1<<62)+1,ore=(1<<62)+1),dict(name='negative_int64',food=-(1<<62)-1),
           dict(name='ore_mode',mode=2,ore=-1),dict(name='other_mode',mode=3,food=-1,ore=-1),
           dict(name='zero_mode',mode=0),dict(name='negative_count',counted_houses=-1),
           dict(name='fractional_center',plot=dict(x=158.25,z=120.125,size=5)),
           dict(name='fractional_cost',cost_override={'18':.3},food=0),
           dict(name='negative_cost',cost_override={'18':-3.},food=-2),
           dict(name='scheme_zero',configuration=dict(biome1Index=0),unlocks=['PlotsAppear','Low_Rank_1'])]
    all_keys=sorted({r['unlock'] for r in extract()['rows']}-{'NeverUnlocked'})
    for profile,keys in [('tent',['PlotsAppear']),('all',all_keys)]:
        for size in [2,4,5,6,7,8,9,10]:
            for height in [6.,7.5,7.500000476837158,10.800000190734863,11.1]:
                cases.append(dict(name=f'{profile}_{size}_{height}',unlocks=keys,plot=dict(size=size,height=height)))
    for case in cases:case['expected']=oracle.observe(case)
    result={key:oracle.content[key] for key in ['source_sha256','table_sha256','executable_sha256','native_routines']}
    result.update(cases=cases,scope=__doc__.strip(),adapters=[hex(a) for a in sorted(oracle.adapters)])
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original plot cost:',len(cases),'cases')


if __name__=='__main__':main()
