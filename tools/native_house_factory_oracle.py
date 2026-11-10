"""Execute original house allocation, plot factory and core constructor together.

Pool capacity/order and existing slot bodies are explicit inputs. Original
allocation, type/rotation choice, constructor/base initialization, occupancy,
footprint unregister and plot free instructions execute. Dynamic stat, model,
field membership, settlement and presentation services remain explicit adapters.
No follower job, full building lifetime or campaign completion is claimed.
"""
import argparse
import json
import struct

from tools.house_selection import extract
from tools.native_house_constructor_oracle import ConstructorOracle
from tools.native_plot_conversion_oracle import ConversionOracle
from tools.native_scenery_oracle import ROOT


class FactoryOracle(ConstructorOracle,ConversionOracle):
    def configure_factory(self,case):
        capacity=case.get('capacity',8)
        self.cpu.mem_write(self.HOUSE_POOL,bytes(capacity*0x2d8))
        self.configure_conversion(case)
        conversion=dict(self.adapters)
        self.HOUSE=self.HOUSE_POOL if case.get('reuse',False) else self.house
        self.configure_constructor(case)
        for handle in self.handles:self.cpu.hook_del(handle)
        constructor=dict(self.adapters)
        self.adapters=conversion|constructor
        for address in [0x100441c0,0x100bc660]:self.adapters.pop(address,None)
        self.profile(dict(unlocks=case.get('unlocks',['PlotsAppear']),biome_locked=case.get('biome_locked',True)))
        houses=case.get('houses',[])
        count=len(houses)
        if count>capacity:raise ValueError('Invalid controlled native house capacity')
        self.set_integer(0x10fcd478,count)
        self.cpu.mem_write(0x10fcd47c,struct.pack('<HH',count if count<capacity else 0xffff,count-1 if count else 0xffff))
        for i in range(capacity):
            pointer=self.HOUSE_POOL+i*0x2d8
            if i<count:
                next_=i-1 if i else 0xffff
                previous=i+1 if i+1<count else 0xffff
            else:
                next_=i+1 if i+1<capacity else 0xffff
                previous=i-1 if i>count else 0xffff
            self.cpu.mem_write(pointer,struct.pack('<HH',next_,previous))
            old=houses[i] if i<count else case.get('stale',{})
            self.set_integer(pointer+0x264,old.get('index',18) if i<count or old else 0)
            self.set_integer(pointer+0x88,old.get('owner',0)<<29)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_constructor,begin=0x100bc660,end=0x100bc660))
        for index in case.get('free_before',[]):
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,0x10fcd474)
            self.call(0x10044250,[self.HOUSE_POOL+index*0x2d8])

    def observe_constructor(self,cpu,address,size,user):
        args=self.arguments(13)
        self.HOUSE=self.cpu.reg_read(self.regs.UC_X86_REG_ECX)
        self.stats=0x10fc241c+args[4]*0x130
        self.request=dict(position=list(struct.unpack('<4f',struct.pack('<4I',*args[:4]))),
                          index=args[4],owner=args[5],extra=args[6],kind=args[7],special=args[8],
                          unknown_a=args[9],unknown_b=args[10],configuration=args[11],reuse=bool(args[12]))

    def pool_snapshot(self):
        def chain(start):
            result=[]
            index=struct.unpack('<H',self.cpu.mem_read(start,2))[0]
            while index!=0xffff:
                if index in result or index>=self.case.get('capacity',8):raise ValueError('Invalid native house pool chain')
                result.append(index)
                index=struct.unpack('<H',self.cpu.mem_read(self.HOUSE_POOL+index*0x2d8,2))[0]
            return result
        return dict(count=self.integer(0x10fcd478),active=chain(0x10fcd47e),free=chain(0x10fcd47c))

    def factory(self):
        result=self.convert()
        result['pool']=self.pool_snapshot()
        result['core']=self.core_snapshot() if result['created'] else None
        result['house_id']=(self.HOUSE-self.HOUSE_POOL)//0x2d8 if result['created'] else -1
        return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_house_factory.json'))
    args=parser.parse_args()
    oracle=FactoryOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    cases=[dict(name='first'),dict(name='full',capacity=2,houses=[{},{}]),
           dict(name='offset',plot=dict(offset=[.25,-.375],rotation=.4)),
           dict(name='rotation',houses=[{}]*3,random_word=16384),
           dict(name='two_matching',houses=[{}]*2,random_word=16384),
           dict(name='stale_matching_slot',houses=[{}]*2,stale=dict(index=18),random_word=16384),
           dict(name='freed_matching_slot',houses=[{}]*3,free_before=[1],random_word=16384),
           dict(name='free_head_order',houses=[{}]*4,free_before=[1,3]),
           dict(name='reuse',reuse=True,houses=[{}]),
           dict(name='owner',owner=2),dict(name='flags',food_enabled=True,ore_enabled=True),
           dict(name='farm',kind=1,special=True,biome_locked=False),
           dict(name='mine',kind=2,special=True,biome_locked=False),
           dict(name='mixed_scenery',nearby=[dict(type=0),dict(type=15,mode=2),dict(type=20)]),
           dict(name='beautified',beauty=.75)]
    for case in cases:
        oracle.configure_factory(case)
        case['expected']=oracle.factory()
        print(case['name'],case['expected']['house_id'],case['expected']['random_calls'],flush=True)
    source=extract()
    result={key:source[key] for key in ['source_sha256','table_sha256','executable_sha256']}
    from tools.house_pool import extract as pool_configuration
    pool=pool_configuration()
    capacity=pool['rules']['capacity']
    oracle.case=dict(capacity=capacity)
    oracle.cpu.mem_write(oracle.HOUSE_POOL,bytes(capacity*pool['stride']))
    oracle.set_integer(0x10fcd474,oracle.HOUSE_POOL)
    oracle.cpu.reg_write(oracle.regs.UC_X86_REG_ECX,0x10fcd474)
    oracle.call(0x1019fbc0)
    result['pool_initialization']=oracle.pool_snapshot()
    result['pool_configuration']=pool
    result.update(cases=cases,adapters=[hex(a) for a in sorted(oracle.adapters)],observers=['0x100bc660'],scope=__doc__.strip(),
                  native_routines={hex(a):oracle.image.read(a,b-a).hex() for a,b in [
                      (0x100441c0,0x1004424c),(0x10044250,0x1004430c),(0x10044cb0,0x10044f97),
                      (0x100bc660,0x100bcb72),(0x1003f610,0x1003f945)]})
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original house factory:',len(cases),'cases')


if __name__=='__main__':main()
