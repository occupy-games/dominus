"""Observe the original follower's construction-start protocol, not quick-build.

The native follower start, plot factory, type selection, placement, rotation and
plot release execute. The full house constructor is still an explicit adapter.
Cost lookup/payment, settlement lookup, target assignment, action transition and
effect delivery are captured service boundaries. No follower movement or full
building lifetime is claimed by these observations.
"""
import argparse
import json
import struct

from tools.native_plot_conversion_oracle import ConversionOracle
from tools.native_scenery_oracle import ROOT


class BuildStartOracle(ConversionOracle):
    ACTOR=0x31800000
    FOLLOWER=0x31801000

    def configure_start(self,case):
        self.configure_conversion(case)
        for handle in self.handles:self.cpu.hook_del(handle)
        self.cpu.mem_write(self.ACTOR,bytes(0x200))
        self.cpu.mem_write(self.FOLLOWER,bytes(0x98))
        self.set_integer(self.ACTOR+0x100,self.FOLLOWER)
        for i,value in enumerate(case.get('position',[161.,123.,6.])):
            self.set_float(self.ACTOR+0x70+4*i,value)
        self.set_integer(self.FOLLOWER+0x10,case.get('owner',0)<<29)
        self.set_integer(self.FOLLOWER+0x38,case.get('settlement',0xffffffff))
        self.operations=[]
        self.transitions=[]
        self.targets=[]
        self.rectangles=[]
        self.effects=[]
        self.attachments=[]
        self.adapters.update({
            0x10124d70:self.settlement,
            0x10124660:self.food_enabled,
            0x10235bd0:self.cost,
            0x10062b20:self.spend,
            0x10124cc0:self.attach,
            0x10033d20:self.target,
            0x1006b2e0:self.transition,
            0x10100890:self.effect,
            0x1012a590:self.rectangle,
            0x10219aa0:self.paid_effect,
            0x10219470:self.paid_effect_finish,
        })
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def settlement(self):
        self.operations.append('settlement')
        self.settlement_position=list(struct.unpack('<3f',struct.pack('<3I',*self.arguments(3))))
        self.return_integer(self.case.get('lookup_settlement',0xffffffff))

    def food_enabled(self):
        self.operations.append('food_enabled')
        self.return_integer(int(self.case.get('food_enabled',False)))

    def cost(self):
        if self.arguments(1)!=(1,) or self.cpu.reg_read(self.regs.UC_X86_REG_ECX)!=self.POOL:
            raise ValueError('Unexpected original plot-cost request')
        self.operations.append('cost')
        self.return_float(self.case.get('cost',0.))

    def spend(self):
        amount=struct.unpack('<f',struct.pack('<I',self.arguments(1)[0]))[0]
        self.operations.append(['spend',amount])
        self.return_integer()

    def allocate_house(self):
        self.operations.append('allocate')
        super().allocate_house()

    def constructor(self):
        self.operations.append('construct')
        super().constructor()
        # These position/identity fields would be initialized by the complete
        # constructor. They are needed by native reference/rectangle helpers.
        for i,value in enumerate(self.request['position'][:3]):self.set_float(self.house+0xb0+4*i,value)
        self.set_integer(self.house+0x88,0x01000001 | self.case.get('owner',0)<<29)

    def attach(self):
        self.operations.append('attach')
        house,settlement=self.arguments(2)
        self.attachments.append([(house-self.HOUSE_POOL)//0x2d8,settlement])
        self.return_integer()

    def target(self):
        if self.cpu.reg_read(self.regs.UC_X86_REG_ECX)!=self.FOLLOWER:raise ValueError('Unexpected follower target owner')
        args=self.arguments(6)
        self.operations.append('target')
        self.targets.append(dict(identity=args[0],house=(args[1]-self.HOUSE_POOL)//0x2d8,
                                 position=list(struct.unpack('<2f',struct.pack('<2I',*args[2:4]))),
                                 flag=bool(args[4]&0xff),action=args[5]))
        self.return_integer(pop=24)

    def transition(self):
        action,reference=self.arguments(2)
        if reference!=self.FOLLOWER+0x1c:raise ValueError('Unexpected target reference for follower transition')
        self.operations.append('transition')
        self.transitions.append(action)
        self.return_integer(pop=8)

    def effect(self):
        owner,category,event,house=self.arguments(4)
        if house!=self.house:raise ValueError('Unexpected construction effect target')
        self.operations.append('effect')
        self.effects.append([owner,category,event])
        self.return_integer()

    def rectangle(self):
        self.operations.append('rectangle')
        self.rectangles.append(list(struct.unpack('<4f',struct.pack('<4I',*self.arguments(4)))))
        self.return_integer()

    def paid_effect(self):
        amount,a,b,house=self.arguments(4)
        if house!=self.house:raise ValueError('Unexpected resource payment effect target')
        self.operations.append(['payment_effect',struct.unpack('<f',struct.pack('<I',amount))[0],a,b])
        self.return_integer(self.SCRATCH+0xa00,pop=16)

    def paid_effect_finish(self):
        self.operations.append('payment_effect_finish')
        self.return_integer()

    def start(self):
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.ACTOR)
        result=self.call(0x1006b4d0,[self.POOL,int(self.case.get('special',False)),self.case.get('kind',0)],limit=4000000)
        return dict(started=bool(result&0xff),request=self.request,operations=self.operations,
                    targets=self.targets,transitions=self.transitions,effects=self.effects,
                    rectangles=self.rectangles,attachments=self.attachments,
                    ground_queries=self.ground_queries,random_calls=self.random_calls,
                    registry=self.snapshot(),
                    dirty=[i for i in range(1024) if self.integer(0x10f6e858+(i//32)*4)&(1<<(i%32))])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_build_start.json'))
    args=parser.parse_args()
    oracle=BuildStartOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    cases=[dict(name='first'),dict(name='failure',allocation_failed=True),
           dict(name='paid',food_enabled=True,cost=3.75),
           dict(name='paid_failure',food_enabled=True,cost=3.75,allocation_failed=True),
           dict(name='free',food_enabled=True,cost=0.),
           dict(name='farm',special=True,kind=1,settlement=9,food_enabled=True,cost=8.),
           dict(name='mine',special=True,kind=2,settlement=13,food_enabled=True,cost=8.),
           dict(name='farm_biome_unlocked',special=True,kind=1,settlement=9,biome_locked=False),
           dict(name='mine_biome_unlocked',special=True,kind=2,settlement=13,biome_locked=False),
           dict(name='special_abode',special=True,kind=0,settlement=5),
           dict(name='owner',owner=3),
           dict(name='offset',plot=dict(offset=[.25,-.375],rotation=.4)),
           dict(name='rotation',houses=[{}]*3,random_word=16384),
           dict(name='settlement',lookup_settlement=7),
           dict(name='negative_cost',food_enabled=True,cost=-1.)]
    for case in cases:
        oracle.configure_start(case)
        case['expected']=oracle.start()
        print(case['name'],case['expected']['started'],case['expected']['operations'],flush=True)
    from tools.house_selection import extract
    source=extract()
    result={key:source[key] for key in ['source_sha256','table_sha256','executable_sha256']}
    result.update(cases=cases,native_routines={hex(a):oracle.image.read(a,b-a).hex() for a,b in [
        (0x1006b4d0,0x1006b687),(0x1016b360,0x1016b3ae),(0x1016adb0,0x1016aeff)]},
        adapters=[hex(a) for a in sorted(oracle.adapters)],
        scope=__doc__.strip())
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original follower construction start:',len(cases),'cases')


if __name__=='__main__':main()
