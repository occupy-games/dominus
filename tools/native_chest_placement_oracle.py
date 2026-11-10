"""Execute original chest placement gates, scenery boxes and building clearances.

Only original field storage, sampled ground height, unlock membership, resolved
special-building references and custom authored shape membership are adapters.
The two restriction gates, height decisions, ordered object traversal, ordinary
scenery footprint, building footprint/corner rules and extra radius execute the
supplied x86 instructions. No original OS, scene, device or entrypoint runs.
"""
import argparse
import hashlib
import json
import random
import struct

from tools.native_scenery_oracle import Oracle, ROOT
from tools.native_storm_chests_oracle import word
from tools.storm_chests import extract


class PlacementOracle(Oracle):
    def configure_placement(self):
        self.adapters={0x10145330:self.category,0x100cf550:self.restriction,0x1025dc10:self.ground,
                       0x1015c1e0:self.unlocked,0x100400b0:self.special,0x1011ac10:self.custom}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def category(self):
        field,x,z=self.arguments(3)
        if field!=2:raise ValueError('Unexpected chest byte field')
        x,z=struct.unpack('<2i',struct.pack('<2I',x,z))
        self.queries.append(['category',x,z])
        self.cpu.mem_write(self.SCRATCH+0x4000,bytes([self.case.get('category',0)]))
        self.return_integer(0 if self.case.get('missing_category',False) else self.SCRATCH+0x4000)

    def restriction(self):
        field,x,z=self.arguments(3)
        if field!=5:raise ValueError('Unexpected chest float field')
        x,z=struct.unpack('<2i',struct.pack('<2I',x,z))
        self.queries.append(['restriction',x,z])
        self.return_float(self.case.get('restriction',0.))

    def ground(self):
        x,z,a,b,c=self.arguments(5)
        if a or b or c:raise ValueError('Unexpected chest ground query flags')
        self.queries.append(['ground',*struct.unpack('<2f',struct.pack('<2I',x,z))])
        self.return_float(self.case.get('height',6.))

    def unlocked(self):
        pointer,=self.arguments(1)
        name=bytes(self.cpu.mem_read(pointer,60)).split(b'\0')[0].decode()
        self.queries.append(['unlock',name])
        self.return_integer(int(name in self.case.get('unlocks',[])))

    def special(self):
        pointer=self.cpu.reg_read(self.regs.UC_X86_REG_ECX)-0x23c
        self.return_integer(int(self.buildings[pointer]['special']))

    def custom(self):
        pointer=self.cpu.reg_read(self.regs.UC_X86_REG_ECX)
        index=(pointer-self.POOL-0x80000)//0x100
        args=self.arguments(5)
        x,z=struct.unpack('<2f',struct.pack('<2I',*args[:2]))
        self.queries.append(['custom',index,int(x),int(z)])
        self.return_integer(int(self.case['scenery'][index].get('custom_result',False)),pop=20)

    def list_at(self,objects,base,kind):
        for index,object in enumerate(objects):
            pointer=self.POOL+base+index*0x1000
            node=self.POOL+0x100000+kind*0x10000+index*32
            entry=self.POOL+0x140000+kind*0x10000+index*16
            self.cpu.mem_write(pointer,bytes(0x400))
            self.set_integer(entry,pointer)
            self.set_integer(node,entry)
            self.set_integer(node+4,node+32 if index+1<len(objects) else 0)
            self.set_integer(node+8,self.POOL+0x180000+kind*0x10000)
            if kind==0:
                self.set_float(pointer+0xb0,object['x'])
                self.set_float(pointer+0xb4,object['z'])
                self.set_integer(pointer+0x154,object['size'])
                self.set_integer(pointer+0x1cc,self.POOL+0x80000+index*0x100 if object['custom'] else 0)
            else:
                self.set_float(pointer+0x278,object['x'])
                self.set_float(pointer+0x27c,object['z'])
                self.set_integer(pointer+0x31c,object['size'])
                self.set_integer(pointer+0x2b4,index)
                self.buildings[pointer]=object
                if object['special']:
                    self.set_integer(0x10bc9878+index*0x180,pointer)
                    self.set_float(0x10bc9850+index*0x180+0x1c,object.get('radius',0.))
        return self.POOL+0x100000+kind*0x10000 if objects else 0

    def observe(self,case,rules):
        self.case=case
        self.queries=[]
        self.buildings={}
        self.cpu.mem_write(0x10bc9850,bytes(40*0x180))
        heads=self.SCRATCH+0x5000
        self.set_integer(heads,self.list_at(case.get('scenery',[]),0x1000,0))
        self.set_integer(heads+4,self.list_at(case.get('buildings',[]),0x40000,1))
        for key,address in [('spawn_padding',0x105d8488),('deep_level',0x105b7424),('high_level',0x105b7428),('min_building_half',0x105d4cb0)]:self.set_float(address,rules[key])
        self.set_integer(0x10d9b664,int(case.get('high_override',False)))
        success=self.call(0x101521e0,[word(case.get('x',160.)),word(case.get('z',120.)),heads])
        return dict(ok=bool(success),queries=self.queries)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_chest_placement.json'))
    args=parser.parse_args()
    content=extract()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    oracle=PlacementOracle(raw)
    oracle.configure_placement()
    cases=[dict(name='clear'),dict(name='missing_category',missing_category=True),
           dict(name='low',height=0.),dict(name='low_unlocked',height=0.,unlocks=['DeepWaterSculpt']),
           dict(name='high',height=12.),dict(name='high_unlocked',height=12.,unlocks=['HighMountainSculpt']),
           dict(name='high_override',height=12.,high_override=True),
           dict(name='low_override_cannot_bypass',height=0.,high_override=True),
           dict(name='round_positive',x=160.49998474121094,z=120.5),dict(name='round_negative',x=-1.5,z=-.75),
           dict(name='offmap',x=1023.5,z=1024.)]
    for category in [0,1,63,64,65,127,128,129,255]:
        for strength in [0.,.1,-.1]:cases.append(dict(name=f'restriction_{category}_{strength}',category=category,restriction=strength))
    for threshold in [14.,35.]:
        # Captured world heights are rounded to float32 by the explicit ground
        # service, preserving the original conversion back into stored steps.
        for height in [threshold/3.3333332538604736-0.000001,threshold/3.3333332538604736,threshold/3.3333332538604736+0.000001]:
            cases.append(dict(name=f'height_boundary_{threshold}_{height}',height=height))
    ordinary=dict(x=160.,z=120.,size=4,custom=False)
    for size in [0,1,2,3,4,5,8]:
        for x,z in [(160.,120.),(156.,120.),(157.,120.),(158.,120.),(162.,120.),(163.,120.),(164.,120.),(157.,117.)]:
            cases.append(dict(name=f'scenery_{size}_{x}_{z}',x=x,z=z,scenery=[dict(ordinary,size=size)]))
    cases.extend([dict(name='custom_clear',scenery=[dict(ordinary,custom=True,custom_result=False)]),
                  dict(name='custom_blocked',scenery=[dict(ordinary,custom=True,custom_result=True)]),
                  dict(name='custom_order',scenery=[dict(ordinary,custom=True,custom_result=False),dict(ordinary,custom=True,custom_result=True),dict(ordinary,custom=True,custom_result=False)])])
    building=dict(x=160.,z=120.,size=4,special=False)
    for special in [False,True]:
        for size in [0,1,2,4,8]:
            for x,z in [(160.,120.),(157.,117.),(156.,116.),(157.,120.),(163.,123.),(164.,124.)]:
                cases.append(dict(name=f'building_{special}_{size}_{x}_{z}',x=x,z=z,buildings=[dict(building,size=size,special=special,radius=0.)]))
    for x in [163.,163.99998474121094,164.,164.00001525878906,165.]:
        cases.append(dict(name=f'special_radius_{x}',x=x,buildings=[dict(building,size=0,special=True,radius=3.)]))
    cases.extend([dict(name='scenery_before_buildings',scenery=[dict(ordinary,custom=True,custom_result=True)],buildings=[building]),
                  dict(name='high_gate_before_objects',height=12.,scenery=[dict(ordinary,custom=True,custom_result=True)]),
                  dict(name='minimum_half',x=164.,buildings=[dict(building,size=0)],rules=dict(min_building_half=4.)),
                  dict(name='fractional_center',x=157.,z=117.,buildings=[dict(building,x=160.125,z=120.375)]),
                  dict(name='padding_zero',x=158.,scenery=[ordinary],rules=dict(spawn_padding=0.))])
    rng=random.Random(18573)
    for i in range(40):
        x,z=160.+rng.uniform(-7,7),120.+rng.uniform(-7,7)
        cases.append(dict(name=f'mixed_{i}',x=x,z=z,
                          scenery=[dict(ordinary,x=160.+rng.uniform(-5,5),z=120.+rng.uniform(-5,5),size=rng.randrange(6)) for _ in range(2)],
                          buildings=[dict(building,x=160.+rng.uniform(-5,5),z=120.+rng.uniform(-5,5),size=rng.randrange(6),special=bool(rng.randrange(2)),radius=rng.uniform(0,5)) for _ in range(2)]))
    for case in cases:case['expected']=oracle.observe(case,dict(content['placement_rules'],**case.get('rules',{})))
    result=dict(executable_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=content['source_sha256'],cases=cases,
                native_routines={key:value for key,value in content['native_routines'].items() if int(key,16) in [0x101521e0,0x101455f0,0x10145670,0x100b64b0,0x1013d3c0,0x1013ca10]},
                adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original chest placement:',len(cases),'native cases',flush=True)


if __name__=='__main__':main()
