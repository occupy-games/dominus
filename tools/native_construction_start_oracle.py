"""Execute the original follower start, full house factory and target assignment.

Allocation, type selection, complete core initialization, plot release, target
validation and worker/skill counters all execute together. Resolved stats, model,
fields, settlement attachment, job skill, costs, action/path transition and
presentation services remain explicit adapters. This is not follower arrival,
active construction work or a complete campaign.
"""
import argparse
import json
import struct

from tools.house_selection import extract
from tools.native_build_start_oracle import BuildStartOracle
from tools.native_house_factory_oracle import FactoryOracle
from tools.native_scenery_oracle import ROOT


class ConstructionStartOracle(FactoryOracle, BuildStartOracle):
    def configure_construction(self, case):
        self.configure_factory(case)
        for handle in self.handles:
            self.cpu.hook_del(handle)
        self.cpu.mem_write(self.ACTOR, bytes(0x200))
        self.cpu.mem_write(self.FOLLOWER, bytes(0x98))
        self.set_integer(self.ACTOR+0x100, self.FOLLOWER)
        for i, value in enumerate(case.get('position', [161., 123., 6.])):
            self.set_float(self.ACTOR+0x70+4*i, value)
        self.set_integer(self.FOLLOWER+0x10, case.get('owner', 0)<<29)
        self.set_integer(self.FOLLOWER+0x38, case.get('settlement', 0xffffffff))
        self.set_integer(self.FOLLOWER+0x3c, case.get('profession', 0))
        self.set_integer(0x10d9b670, case.get('local_owner', 0))
        self.cpu.mem_write(0x10bc9850, bytes(40*0x180))
        for base, size, header in [(0x10f928e8, 0xc004, 0x10fcd474),
                                   (0x10f8f8e4, 0x3004, 0x10f8f8d8)]:
            self.cpu.mem_write(base, bytes(size))
            self.set_integer(base, header)
        self.operations=[]
        self.transitions=[]
        self.targets=[]
        self.rectangles=[]
        self.effects=[]
        self.attachments=[]
        self.skill_calls=0
        self.settlement_queries=[]
        self.adapters.update({
            0x10124d70:self.settlement,
            0x10235bd0:self.cost,
            0x10062b20:self.spend,
            0x10124cc0:self.attach,
            0x10034650:self.skill,
            0x1006b2e0:self.transition,
            0x10100890:self.effect,
            0x1012a590:self.rectangle,
            0x10219aa0:self.paid_effect,
            0x10219470:self.paid_effect_finish,
            0x10354450:lambda:self.return_integer(),
        })
        # Keep the target setter and both constructors executing their own code.
        self.adapters.pop(0x10033d20, None)
        if case.get('native_cost',False):self.adapters.pop(0x10235bd0,None)
        self.set_integer(0x107d1b44,case.get('counted_houses',1))
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_constructor,begin=0x100bc660,end=0x100bc660))
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_target,begin=0x10033d20,end=0x10033d20))
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.FOLLOWER+0x1c)
        self.call(0x1016ad70)
        if case.get('plot_target',False):
            center=[self.plot['x']+self.plot['size']*.5,self.plot['z']+self.plot['size']*.5]
            self.cpu.mem_write(self.FOLLOWER+0x1c,struct.pack('<IIffI',7<<24,self.POOL,*center,1))
            self.set_integer(0x10f8f8e4+0x1004,1)
            self.set_float(0x10f8f8e4+0x2004,case.get('skill',1.))

    def attach(self):
        house, settlement=self.arguments(2)
        self.attachments.append([(house-self.HOUSE_POOL)//0x2d8,settlement])
        # The attachment service supplies membership; its full compression and
        # lifetime rules are outside this capture, not replaced by this adapter.
        self.set_integer(house+0xec,self.case.get('attachment_index',-1))
        self.return_integer()

    def settlement(self):
        self.settlement_queries.append(list(struct.unpack('<3f',struct.pack('<3I',*self.arguments(3)))))
        BuildStartOracle.settlement(self)

    def observe_constructor(self,cpu,address,size,user):
        super().observe_constructor(cpu,address,size,user)
        self.house=self.HOUSE

    def observe_target(self,cpu,address,size,user):
        args=self.arguments(6)
        self.targets.append(dict(identity=args[0],house=(args[1]-self.HOUSE_POOL)//0x2d8,
                                 position=list(struct.unpack('<2f',struct.pack('<2I',*args[2:4]))),
                                 flag=bool(args[4]&255),action=args[5]))

    def skill(self):
        self.skill_calls+=1
        self.return_float(self.case.get('skill',1.))

    def execute(self):
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.ACTOR)
        result=self.call(0x1006b4d0,[self.POOL,int(self.case.get('special',False)),self.case.get('kind',0)],limit=5000000)
        identity,pointer,x,z,flag=struct.unpack('<5I',self.cpu.mem_read(self.FOLLOWER+0x1c,20))
        counters=dict(houses={},plots={},settlements={})
        for group,base,capacity in [('houses',0x10f928e8,4096),('plots',0x10f8f8e4,1024)]:
            for i in range(self.case.get('capacity',8) if group=='houses' else 1):
                row=[self.integer(base+4+4*i),self.integer(base+4+4*capacity+4*i),self.float(base+4+8*capacity+4*i)]
                if any(row):counters[group][str(i)]=row
        for i in range(40):
            row=[self.integer(0x10bc9850+i*0x180+0x110),self.integer(0x10bc9850+i*0x180+0x114)]
            if any(row):counters['settlements'][str(i)]=row
        return dict(started=bool(result&255),request=self.request,
                    pool=self.pool_snapshot(),core=self.core_snapshot() if result&255 else None,
                    registry=self.snapshot(),
                    target=dict(identity=identity,entity=(pointer-self.HOUSE_POOL)//0x2d8 if pointer else -1,
                                position=list(struct.unpack('<2f',struct.pack('<2I',x,z))),flag=bool(flag&255)),
                    counters=counters,skill_calls=self.skill_calls,targets=self.targets,
                    transitions=self.transitions,effects=self.effects,rectangles=self.rectangles,
                    attachments=self.attachments,spending=[entry[1] for entry in self.operations if isinstance(entry,list) and entry[0]=='spend'],
                    settlement_queries=self.settlement_queries,
                    payment_effects=[entry[1:] for entry in self.operations if isinstance(entry,list) and entry[0]=='payment_effect'],
                    random_calls=self.random_calls,ground_queries=self.ground_queries,
                    dirty=[i for i in range(1024) if self.integer(0x10f6e858+(i//32)*4)&(1<<(i%32))])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_construction_start.json'))
    args=parser.parse_args()
    oracle=ConstructionStartOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    cases=[dict(name='first'),dict(name='paid',food_enabled=True,cost=3.75),
           dict(name='full',capacity=2,houses=[{},{}]),
           dict(name='paid_full',capacity=2,houses=[{},{}],food_enabled=True,cost=3.75),
           dict(name='fractional_skill',skill=.3),dict(name='zero_skill',skill=0.),
           dict(name='owner',owner=2),dict(name='profession',profession=8),
           dict(name='foreign_profession',profession=8,owner=1),
           dict(name='settlement',lookup_settlement=7,attachment_index=7),
           dict(name='settled',settlement=4,lookup_settlement=7,attachment_index=7),
           dict(name='farm',special=True,kind=1,settlement=9,attachment_index=9,biome_locked=False),
           dict(name='mine',special=True,kind=2,settlement=13,attachment_index=13,biome_locked=False),
           dict(name='offset',plot=dict(offset=[.25,-.375],rotation=.4)),
           dict(name='rotation',houses=[{}]*3,random_word=16384),
           dict(name='freed_slot',houses=[{}]*3,free_before=[1],random_word=16384),
           dict(name='identity_high',next_identity=0x1ffffff),
           dict(name='identity_wrap',next_identity=0xffffffff),
           dict(name='prior_plot_target',plot_target=True,skill=.3),
           dict(name='source_food',native_cost=True,food_enabled=True),
           dict(name='source_first_free',native_cost=True,food_enabled=True,counted_houses=0),
           dict(name='source_settlement_free',native_cost=True,food_enabled=True,lookup_settlement=7,attachment_index=7),
           dict(name='source_paid_full',native_cost=True,food_enabled=True,capacity=2,houses=[{},{}]),
           dict(name='source_lowland',native_cost=True,food_enabled=True,plot=dict(size=5),unlocks=['PlotsAppear','Low_Rank_1']),
           dict(name='scenery',nearby=[dict(type=0),dict(type=15,mode=2),dict(type=20)],beauty=.75)]
    for case in cases:
        oracle.configure_construction(case)
        case['adapters']=[hex(a) for a in sorted(oracle.adapters)]
        case['expected']=oracle.execute()
        print(case['name'],case['expected']['started'],case['expected']['counters'],flush=True)
    result={key:extract()[key] for key in ['source_sha256','table_sha256','executable_sha256']}
    result.update(cases=cases,scope=__doc__.strip(),adapters=[hex(a) for a in sorted(oracle.adapters)],
                  observers=['0x100bc660','0x10033d20'],
                  native_routines={hex(a):oracle.image.read(a,b-a).hex() for a,b in [
                      (0x1006b4d0,0x1006b687),(0x100441c0,0x1004424c),
                      (0x10044cb0,0x10044f97),(0x100bc660,0x100bcb72),(0x1003f610,0x1003f945),
                      (0x10033d20,0x10033d56),(0x100caf60,0x100cb0a2),(0x1016af00,0x1016b133)]})
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original integrated construction start:',len(cases),'cases')


if __name__=='__main__':main()
