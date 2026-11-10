"""Execute original chest numeric initialization and its actual factory caller.

The complete original constructor runs. Renderer/animation resource factories,
heap storage, ground samples, seeded CRT words, and spatial-index insertion are
explicit adapters. Numeric writes, burial/clamping, spatial-record initialization,
random timer arithmetic, factory source-ID/reward ordering and notification position
execute original instructions. No original device, OS or entrypoint runs.
"""
import argparse
import json
import struct

from tools.native_chest_factory_oracle import FactoryOracle
from tools.native_scenery_oracle import ROOT
from tools.native_storm_chests_oracle import word
from tools.storm_chests import extract


class ConstructorOracle(FactoryOracle):
    def configure_core(self,composed=False):
        self.adapters={0x1025c150:self.ground,0x1035f7f0:self.random,0x1012ddd0:self.register,
                       0x10353740:lambda:self.return_integer(self.POOL+0x10000),
                       0x10334ee9:lambda:self.return_integer(self.POOL+0x10000),
                       0x10335008:lambda:self.return_integer(pop=4),
                       0x10335ee9:lambda:self.return_integer(pop=16),
                       0x10335051:lambda:self.return_integer(),
                       0x10102b70:lambda:self.return_integer(pop=24),
                       0x10077a20:lambda:self.return_integer(pop=8),
                       0x100779e0:lambda:self.return_integer(pop=12),
                       0x1003c9b0:lambda:self.return_integer(),
                       0x10082150:lambda:self.return_integer(pop=4),
                       0x1003c7d0:lambda:self.return_integer(pop=4)}
        if composed:self.adapters.update({0x10094380:self.allocate,0x101b51e0:self.identifier,0x101b5260:self.hash,0x1024d580:self.notify})
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        # This observer never returns or skips an instruction in the constructor.
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.enter,begin=0x101523c0,end=0x101523c0))
        self.composed=composed

    def enter(self,cpu,address,size,user):
        args=self.arguments(6)
        values=struct.unpack('<5f',struct.pack('<5I',*args[:5]))
        self.request=dict(position=list(values[:3]),depth=values[3],rotation=values[4],kind=args[5])
        self.events.append(['construct',self.request])

    def ground(self):
        x,z,extra=self.arguments(3)
        if extra:raise ValueError('Unexpected ground flags')
        self.events.append(['ground',*struct.unpack('<2f',struct.pack('<2I',x,z))])
        values=self.case.get('ground_heights',[self.case.get('height',6.)])
        value=values[min(self.ground_calls,len(values)-1)]
        self.ground_calls+=1
        self.return_float(value)

    def register(self):
        pointer,=self.arguments(1)
        if pointer!=self.POOL+0x78:raise ValueError('Unexpected spatial record')
        self.registered=True
        self.events.append(['register',dict(kind=self.integer(pointer+8),position=[self.float(pointer+0x10),self.float(pointer+0x14)],radius=self.float(pointer+0xc),flag=1)])
        self.return_integer(123)

    def snapshot(self):
        slots={key:self.integer(self.POOL+int(key,16)) for key in ['60','6c','70','a0','a4']}
        slots.update({key:self.float(self.POOL+int(key,16)) for key in ['1c','58','9c']})
        slots['98']=bool(self.cpu.mem_read(self.POOL+0x98,1)[0])
        x,z,height=struct.unpack('<3f',self.cpu.mem_read(self.POOL+0x44,12))
        return dict(kind=self.integer(self.POOL+0x50),position=[x,z,height],base_height=self.float(self.POOL+0x5c),
                    rotation=self.float(self.POOL+0x64),source_slots=slots,registered=self.registered,
                    spatial=dict(kind=self.integer(self.POOL+0x80),position=[self.float(self.POOL+0x88),self.float(self.POOL+0x8c)],radius=self.float(self.POOL+0x84),flag=1))

    def observe_core(self,case,content):
        self.case=case
        self.events=[]
        self.request=None
        self.reward=''
        self.random_calls=0
        self.ground_calls=0
        self.registered=False
        self.cpu.mem_write(self.POOL,bytes(0xa8))
        self.set_integer(self.POOL+4,7)
        self.set_integer(self.POOL+0x68,74565)
        self.set_float(self.POOL+0x54,123.25)
        self.set_integer(0x10bb2a0c,0) # No renderer resource table; presentation calls are adapters.
        rules=dict(content['core_rules'],**case.get('core_rules',{}))
        self.set_float(0x105d809c,rules['glint_min'])
        self.set_float(0x105d8478,rules['glint_max'])
        if self.composed:
            rules=dict(content['factory_rules'],**case.get('factory_rules',{}))
            for key,address in [('second_level',0x105d848c),('third_level',0x105d8490),('rotation',0x105d8494),('story_odds',0x105d8498)]:self.set_float(address,rules[key])
            self.call(0x10152ed0,[word(case.get('x',160.)),word(case.get('z',120.)),word(case.get('depth',0.))])
        else:
            req=case['request']
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.POOL)
            self.call(0x101523c0,[word(value) for value in req['position']]+[word(req['depth']),word(req['rotation']),req['kind']])
        return dict(record=self.snapshot() if self.request else None,request=self.request,events=self.events,random_calls=self.random_calls,
                    source_id=self.integer(self.POOL+4),reward=self.reward,untouched_depth=self.float(self.POOL+0x54),
                    untouched_reward=self.integer(self.POOL+0x68) if not self.composed else None)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_chest_constructor.json'))
    args=parser.parse_args()
    content=extract()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    oracle=ConstructorOracle(raw)
    oracle.configure_core()
    request=dict(position=[160.,120.,99.],depth=0.,rotation=180.,kind=0)
    cases=[]
    for kind in range(5):
        for height in [0.,.3,.3000001,5.7,6.,14.]:
            for depth in [0.,1.,3.]:cases.append(dict(name=f'kind_{kind}_height_{height}_depth_{depth}',request=dict(request,kind=kind,depth=depth),height=height))
    for value in [0,1,16383,16384,32767]:cases.append(dict(name=f'timer_{value}',request=request,word=value))
    for x,z in [(-1.,120.),(-.5,120.),(1024.,1024.),(1024.5,120.),(1025.,120.),(160.,-1.),(160.,1025.)]:
        cases.append(dict(name=f'spatial_{x}_{z}',request=dict(request,position=[x,z,0.])))
    cases.extend([dict(name='fractional',request=dict(request,position=[160.125,120.375,-55.],depth=.75,rotation=123.25)),
                  dict(name='negative_depth',request=dict(request,depth=-2.25)),
                  dict(name='equal_timer',request=request,core_rules=dict(glint_min=.3,glint_max=.3),word=13241),
                  dict(name='reversed_timer',request=request,core_rules=dict(glint_min=8.,glint_max=4.),word=13241)])
    for case in cases:case['expected']=oracle.observe_core(case,content)
    composed=ConstructorOracle(raw)
    composed.configure_core(composed=True)
    batches=[dict(name='ordinary'),dict(name='story',word=0),dict(name='buried',depth=3.),
             dict(name='clamped',height=0.,depth=3.),dict(name='fractional',x=160.125,z=120.375,depth=.75),
             dict(name='independent_ground',ground_heights=[12.,6.]),dict(name='allocation_failed',allocation_failed=True)]
    for case in batches:case['expected']=composed.observe_core(case,content)
    result=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],cases=cases,composed=batches,
                native_routines={key:content['native_routines'][key] for key in ['0x101523c0','0x100f1a00','0x10152ed0']},
                adapters=[hex(a) for a in sorted(oracle.adapters)],composed_adapters=[hex(a) for a in sorted(composed.adapters)],
                observation_hooks=['0x101523c0'],scope=__doc__.strip())
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original chest constructor:',len(cases),'core cases,',len(batches),'factory cases',flush=True)


if __name__=='__main__':main()
