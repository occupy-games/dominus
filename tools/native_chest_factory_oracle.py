"""Capture the original chest factory's ordering and constructor/reward requests.

Runs 0x10152ed0 with explicit allocation, sampled ground, deterministic CRT words,
constructor and identifier-storage services. The original height classification,
story decision, generated source-ID write, reward choice and notification ordering
execute unchanged. Core chest construction and reward redemption are not replaced
by this comparison, and no original device/OS/entrypoint executes.
"""
import argparse
import json
import struct

from tools.native_scenery_oracle import Oracle, ROOT
from tools.native_storm_chests_oracle import word
from tools.storm_chests import extract


class FactoryOracle(Oracle):
    def configure_factory(self):
        self.adapters={0x10094380:self.allocate,0x1025c150:self.ground,0x1035f7f0:self.random,
                       0x101523c0:self.construct,0x101b51e0:self.identifier,0x101b5260:self.hash,
                       0x1024d580:self.notify}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def allocate(self):
        self.events.append(['allocate'])
        self.return_integer(0 if self.case.get('allocation_failed',False) else self.POOL)

    def ground(self):
        x,z,extra=self.arguments(3)
        if extra:raise ValueError('Unexpected chest ground flags')
        self.events.append(['ground',*struct.unpack('<2f',struct.pack('<2I',x,z))])
        self.return_float(self.case.get('height',6.))

    def random(self):
        self.random_calls+=1
        self.events.append(['random'])
        self.return_integer(self.case.get('word',32767))

    def construct(self):
        args=self.arguments(6)
        values=struct.unpack('<5f',struct.pack('<5I',*args[:5]))
        self.request=dict(position=list(values[:3]),depth=values[3],rotation=values[4],kind=args[5])
        self.events.append(['construct',self.request])
        self.cpu.mem_write(self.POOL+0x44,struct.pack('<3f',*self.case.get('constructed_position',values[:3])))
        for _ in range(self.case.get('construct_random',0)):
            self.random_calls+=1
            self.events.append(['random'])
        self.return_integer(pop=24)

    def identifier(self):
        pointer,=self.arguments(1)
        self.reward=bytes(self.cpu.mem_read(pointer,80)).split(b'\0')[0].decode()
        self.events.append(['reward',self.integer(self.POOL+4),self.reward])
        self.return_integer(pop=4)

    def hash(self):self.return_integer(123456)

    def notify(self):
        _,pointer,extra=self.arguments(3)
        if extra:raise ValueError('Unexpected chest notification flags')
        position=list(struct.unpack('<3f',self.cpu.mem_read(pointer,12)))
        self.events.append(['notify',position])
        self.return_integer()

    def observe(self,case,rules):
        self.case=case
        self.events=[]
        self.request=None
        self.reward=''
        self.random_calls=0
        self.cpu.mem_write(self.POOL,bytes(0xa8))
        self.set_integer(self.POOL+4,7) # Prove the original resets this after construction.
        for key,address in [('second_level',0x105d848c),('third_level',0x105d8490),('rotation',0x105d8494),('story_odds',0x105d8498)]:self.set_float(address,rules[key])
        self.call(0x10152ed0,[word(case.get('x',160.)),word(case.get('z',120.)),word(case.get('depth',0.))])
        return dict(request=self.request,reward=self.reward,source_id=self.integer(self.POOL+4),events=self.events,random_calls=self.random_calls)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_chest_factory.json'))
    args=parser.parse_args()
    content=extract()
    oracle=FactoryOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_factory()
    cases=[dict(name='allocation_failed',allocation_failed=True),dict(name='ordinary'),dict(name='story',word=0),
           dict(name='story_below_half',word=16383),dict(name='ordinary_above_half',word=16384),
           dict(name='odds_zero',word=0,rules=dict(story_odds=0.)),dict(name='odds_one_endpoint',word=32767,rules=dict(story_odds=1.)),
           dict(name='negative_depth',depth=-2.),dict(name='buried',depth=3.),dict(name='fractional',x=160.125,z=120.375,depth=.75),
           dict(name='rotation',rules=dict(rotation=123.25)),
           dict(name='constructed_position',constructed_position=[160.25,120.5,5.7]),
           dict(name='constructor_rng',construct_random=3)]
    for height in [0.,5.7,6.,7.5,10.,12.3,14.]:
        for depth in [0.,1.,2.]:cases.append(dict(name=f'type_{height}_{depth}',height=height,depth=depth))
    for level in [19.,25.,41.]:
        for delta in [-.000001,0.,.000001]:
            cases.append(dict(name=f'boundary_{level}_{delta}',height=level/content['factory_rules']['inverse_height_scale']+delta))
    for case in cases:case['expected']=oracle.observe(case,dict(content['factory_rules'],**case.get('rules',{})))
    result=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],cases=cases,
                native_routines={'0x10152ed0':content['native_routines']['0x10152ed0']},adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original chest factory:',len(cases),'native cases',flush=True)


if __name__=='__main__':main()
