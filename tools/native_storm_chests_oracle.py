"""Bounded original storm-end chest budgeting and disk sampling comparisons.

Executes the original region eligibility and refill routines over explicit
area/chest records. Placement is captured, with explicit intervening RNG use.
The disk sampler executes separately with an explicit acceptance predicate.
No entrypoint, host OS, rendering, audio, filesystem or clock runs in the CPU.
"""
import argparse
import json
import random
import struct

from tools.native_scenery_oracle import Oracle, ROOT
from tools.storm_chests import extract


def word(value):
    return struct.unpack('<I',struct.pack('<f',value))[0]


class ChestOracle(Oracle):
    def configure_chests(self):
        self.adapters={0x1035f7f0:self.random,0x1015c130:self.unlocked,0x1022aed0:self.activated,
                       0x10153030:self.place,0x10168e25:self.counts,
                       self.SCRATCH+0x2000:self.accept}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def next_word(self):
        words=self.case.get('words',[32767])
        value=words[self.random_calls%len(words)]
        self.random_calls+=1
        return value

    def random(self):self.return_integer(self.next_word())

    def unlocked(self):
        key,=self.arguments(1)
        self.queries.append(['unlock',key-1])
        self.return_integer(int(key-1 in self.case.get('unlocked',[])))

    def activated(self):
        index,=self.arguments(1)
        self.queries.append(['activated',index])
        self.return_integer(int(index in self.case.get('activated',[])))

    def counts(self):
        frame=self.cpu.reg_read(self.regs.UC_X86_REG_EBP)
        self.observed_counts=list(struct.unpack('<'+'I'*len(self.case['areas']),self.cpu.mem_read(frame-0x104,4*len(self.case['areas']))))
        # Observe before the original fcompp; never replace that instruction.

    def place(self):
        args=self.arguments(6)
        values=struct.unpack('<3f',struct.pack('<3I',*args[:3]))
        depth=struct.unpack('<f',struct.pack('<I',args[4]))[0]
        count=struct.unpack('<i',struct.pack('<I',args[3]))[0]
        self.requests.append(dict(x=values[0],z=values[1],radius=values[2],count=count,max_depth=depth,debug=bool(args[5])))
        for _ in range(self.case.get('placement_random',0)):self.next_word()
        self.return_integer()

    def accept(self):
        args=self.arguments(3)
        self.samples.append(list(struct.unpack('<2f',struct.pack('<2I',*args[:2]))))
        self.return_integer(int(len(self.samples)>=self.case.get('accept_at',1)))

    def replenish(self,case,rules):
        self.case=case
        self.random_calls=0
        self.queries=[]
        self.requests=[]
        self.observed_counts=[]
        self.cpu.mem_write(0x10fcc2f8,bytes(65*52))
        for i,area in enumerate(case['areas']):
            pointer=0x10fcc2f8+i*52
            self.set_integer(pointer+4,i+1)
            self.set_integer(pointer+24,int(area['force']))
            for key,offset in [('x',12),('z',16),('radius',20)]:self.set_float(pointer+offset,area[key])
            for key,offset in [('max_spawn',36),('max_depth',40),('max_total',44)]:self.set_integer(pointer+offset,area[key])
        self.set_float(0x10fcc2f8+len(case['areas'])*52+20,-1.)
        chests=case.get('chests',[])
        self.set_integer(0x10fcd48c,self.POOL)
        self.set_integer(0x10fcd496,0 if chests else 0xffff)
        for i,chest in enumerate(chests):
            pointer=self.POOL+i*0xa8
            self.cpu.mem_write(pointer,bytes(0xa8))
            self.set_integer(pointer,i+1 if i+1<len(chests) else 0xffff)
            self.set_integer(pointer+4,chest['source_id'])
            self.set_integer(pointer+0x60,chest.get('phase',0))
            self.set_float(pointer+0x44,chest['x'])
            self.set_float(pointer+0x48,chest['z'])
        self.set_float(0x10d4fac4,1. if rules['enabled'] else 0.)
        self.set_float(0x105de6bc,rules['influence_padding'])
        self.set_float(0x10d4fac0,rules['debug_count'])
        self.call(0x10168d00)
        return dict(counts=self.observed_counts,requests=self.requests,random_calls=self.random_calls,queries=self.queries)

    def sample(self,case,rules):
        self.case=case
        self.random_calls=0
        self.samples=[]
        self.set_float(0x105e35b0,rules['attempts'])
        self.cpu.mem_write(self.SCRATCH+0x2000,b'\xc3')
        self.cpu.mem_write(self.SCRATCH+0x3000,bytes(8))
        success=self.call(0x1019f2c0,[word(case['x']),word(case['z']),word(case['radius']),self.SCRATCH+0x2000,0,self.SCRATCH+0x3000])
        return dict(ok=bool(success),position=list(struct.unpack('<2f',self.cpu.mem_read(self.SCRATCH+0x3000,8))) if self.samples else [],
                    samples=self.samples,attempts=len(self.samples),random_calls=self.random_calls)


class GenerationOracle(ChestOracle):
    def configure_generation(self):
        self.adapters={0x1035f7f0:self.random,0x1003fee0:self.stats,0x1012ec90:self.nearby,
                       0x101521e0:self.predicate,0x10152ed0:self.create,0x100e54b0:self.release}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def stats(self):
        pointer,=self.arguments(1)
        index=(pointer-0x10c980e8)//4
        self.stats_calls+=1
        self.set_float(self.POOL+0x10,self.case.get('widths',[1.,2.,3.,4.])[index])
        self.return_integer(self.POOL,pop=4)

    def nearby(self):
        args=self.arguments(10)
        self.queries.append(dict(kind=args[0],position=list(struct.unpack('<3f',struct.pack('<3I',*args[1:4]))),flags=list(args[4:])))
        self.return_integer(args[0]) # Opaque plain handles; narrow-phase is explicit.

    def predicate(self):
        args=self.arguments(3)
        self.samples.append(list(struct.unpack('<2f',struct.pack('<2I',*args[:2]))))
        self.return_integer(int(not self.case.get('reject',False) and len(self.samples)%self.case.get('accept_every',1)==0))

    def create(self):
        self.created.append(dict(zip(['x','z','depth'],struct.unpack('<3f',struct.pack('<3I',*self.arguments(3))))))
        for _ in range(self.case.get('create_random',0)):self.next_word()
        self.return_integer()

    def release(self):
        pointer,_=self.arguments(2)
        self.released.append(self.integer(pointer))
        self.return_integer()

    def generate(self,case,rules):
        self.case=case
        self.random_calls=0
        self.stats_calls=0
        self.queries=[]
        self.samples=[]
        self.created=[]
        self.released=[]
        self.set_float(0x105e35b0,rules['attempts'])
        req=case['request']
        self.call(0x10153030,[word(req[k]) for k in ['x','z','radius']]+[req['count'],word(req['max_depth']),0])
        return dict(created=self.created,random_calls=self.random_calls,stats_calls=self.stats_calls,queries=self.queries,samples=self.samples,released=self.released)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_storm_chests.json'))
    args=parser.parse_args()
    content=extract()
    oracle=ChestOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_chests()
    area=dict(unlock='area',x=160.,z=120.,radius=20.,force=True,max_spawn=4,max_depth=2,max_total=5)
    cases=[dict(name='empty',areas=[area]),dict(name='disabled',areas=[area],rules=dict(enabled=False)),
           dict(name='zero_draw',areas=[area],words=[0]),dict(name='half_draw',areas=[area],words=[16384]),
           dict(name='locked',areas=[dict(area,force=False)]),dict(name='unlocked',areas=[dict(area,force=False)],unlocked=[0]),
           dict(name='activated',areas=[dict(area,force=False)],activated=[0]),
           dict(name='authored_id',areas=[area],chests=[dict(x=160.,z=120.,source_id=1)]),
           dict(name='another_authored_id',areas=[area],chests=[dict(x=160.,z=120.,source_id=2)]),
           dict(name='opening_generated',areas=[area],chests=[dict(x=160.,z=120.,source_id=0,phase=1)]),
           dict(name='opened_generated',areas=[area],chests=[dict(x=160.,z=120.,source_id=0,phase=2)]),
           dict(name='full',areas=[area],chests=[dict(x=160.,z=120.,source_id=0) for _ in range(5)]),
           dict(name='overfull',areas=[area],chests=[dict(x=160.,z=120.,source_id=0) for _ in range(6)]),
           dict(name='last_slot',areas=[area],chests=[dict(x=160.,z=120.,source_id=0) for _ in range(4)]),
           dict(name='boundary',areas=[area],chests=[dict(x=180.,z=120.,source_id=0),dict(x=180.00001525878906,z=120.,source_id=0)]),
           dict(name='zero_radius',areas=[dict(area,radius=0.)],chests=[dict(x=160.,z=120.,source_id=0)]),
           dict(name='no_areas',areas=[]),dict(name='overlap',areas=[area,dict(area,x=165.)],chests=[dict(x=160.,z=120.,source_id=0)]),
           dict(name='placement_rng',areas=[area,area,area],words=[32767,0,16384,1,8192,25000],placement_random=2),
           dict(name='debug_fraction',areas=[area],rules=dict(debug_count=2.75)),
           dict(name='debug_negative',areas=[area],rules=dict(debug_count=-2.75)),
           dict(name='zero_spawn',areas=[dict(area,max_spawn=0)]),
           dict(name='64_areas',areas=[dict(area,force=False) for _ in range(64)])]
    rng=random.Random(4317)
    for i in range(30):
        areas=[dict(area,x=160.+rng.uniform(-20,20),z=120.+rng.uniform(-20,20),radius=rng.uniform(0,30),max_spawn=rng.randrange(6),max_total=rng.randrange(6)) for _ in range(4)]
        chests=[dict(x=160.+rng.uniform(-30,30),z=120.+rng.uniform(-30,30),source_id=rng.randrange(3)) for _ in range(20)]
        cases.append(dict(name=f'mixed_{i}',areas=areas,chests=chests,words=[rng.randrange(32768) for _ in range(12)]))
    for case in cases:
        rules=dict(content['rules'],**case.get('rules',{}))
        case['expected']=oracle.replenish(case,rules)
    samples=[]
    for i,words in enumerate([[0,0,0],[0,32767,0],[32767,32767,32767],[16384,16384,16384],[8192,2000,13000],[23413,27459,1246]]):
        samples.append(dict(name=f'disk_{i}',x=160.,z=120.,radius=17.,words=words))
    samples.extend([dict(name='retry',x=160.125,z=120.375,radius=17.25,words=[1234,27001,9182,29384,32767,0],accept_at=4),
                    dict(name='reject',x=160.,z=120.,radius=17.,words=[31767,1234,30000],accept_at=101),
                    dict(name='negative_radius',x=160.,z=120.,radius=-2.,words=[8192,10000,15000]),
                    dict(name='zero_attempts',x=160.,z=120.,radius=17.,rules=dict(attempts=0))])
    for sample in samples:
        sample['expected']=oracle.sample(sample,dict(content['rules'],**sample.get('rules',{})))
    generation=GenerationOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    generation.configure_generation()
    request=dict(x=160.,z=120.,radius=17.,count=1,max_depth=2.)
    batches=[]
    for value in [0,5461,5462,16383,16384,27305,27306,32767]:
        batches.append(dict(name=f'depth_{value}',request=request,words=[0,10000,12000,value]))
    batches.extend([dict(name='multiple',request=dict(request,count=3),words=[12345,27127,15767,10001,32767,3,17824,0],create_random=2),
                    dict(name='retry',request=dict(request,count=2),accept_every=3,words=[1234,5678,10101,17171,23232,32767]),
                    dict(name='reject',request=dict(request,count=2),reject=True,rules=dict(attempts=3)),
                    dict(name='zero',request=dict(request,count=0)),
                    dict(name='negative',request=dict(request,count=-2)),
                    dict(name='negative_padding',request=request,widths=[-1.,-2.,-3.,-4.]),
                    dict(name='fractional_widths',request=request,widths=[.125,2.75,1.5,.7])])
    for batch in batches:batch['expected']=generation.generate(batch,dict(content['rules'],**batch.get('rules',{})))
    result=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],
                native_routines=content['native_routines'],cases=cases,samples=samples,batches=batches,
                adapters=[hex(a) for a in sorted(oracle.adapters)],generation_adapters=[hex(a) for a in sorted(generation.adapters)],scope=__doc__.strip())
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original storm chests:',len(cases),'refill cases,',len(samples),'disk cases,',len(batches),'batches',flush=True)


if __name__=='__main__':main()
