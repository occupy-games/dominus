"""Execute original reward weighted selection and era helpers.

Only the CRT random-word source is adapted. All roll multiplication/wrap,
override handling, empty-bag behavior, ordered comparisons and era conversion
instructions execute. Reward candidate construction/redemption is separate.
"""
import json
import random

from tools.native_scenery_oracle import Oracle, ROOT
from tools.storm_chests import extract


class WeightedOracle(Oracle):
    def configure(self):
        self.adapters={0x1035f7f0:self.word}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def word(self):
        self.calls+=1
        self.return_integer(self.random)

    def choose(self,case):
        self.calls=0
        self.random=case['word']
        self.set_integer(self.POOL,len(case['entries']))
        self.set_integer(self.POOL+4,case['total'])
        for index,entry in enumerate(case['entries']):
            self.set_integer(self.POOL+8+index*8,entry['weight'])
            self.set_integer(self.POOL+12+index*8,entry['value'])
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.POOL)
        value=self.call(0x1004da90,[case['override']])
        return dict(value=value,random_calls=self.calls)


def main():
    content=extract()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    oracle=WeightedOracle(raw)
    oracle.configure()
    examples=[]
    bags=[[],[dict(weight=0,value=10)],[dict(weight=1,value=10)],
          [dict(weight=2,value=11),dict(weight=0,value=12),dict(weight=3,value=13)],
          [dict(weight=0xffffffff,value=21),dict(weight=2,value=22)],
          [dict(weight=1000,value=1),dict(weight=8000,value=2),dict(weight=1000,value=3)]]
    for index,bag in enumerate(bags):
        for override in [0,1,32767,32768,65535,65536,65537,0xffffffff]:
            for word in [0,1,16384,32767,0xffffffff]:
                examples.append(dict(name=f'bag{index}_{override}_{word}',entries=bag,total=sum(e['weight'] for e in bag)&0xffffffff,override=override,word=word))
    rng=random.Random(0x4da90)
    for index in range(80):
        bag=[dict(weight=rng.getrandbits(32),value=i+1) for i in range(rng.randrange(1,10))]
        examples.append(dict(name='unsigned_'+str(index),entries=bag,total=rng.getrandbits(32),override=rng.getrandbits(32) if index%2 else 0,word=rng.getrandbits(32)))
    for case in examples:case['expected']=oracle.choose(case)
    eras=[]
    for value in [0,1,2,3,4,5,6,100,0x7fffffff,0xfffffffe,0xffffffff]:
        eras.append(dict(value=value,bucket=oracle.call(0x1004d2d0,[value]),era=oracle.call(0x1004d300,[value])))
    result=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],cases=examples,eras=eras,
                native_routines={hex(a):oracle.image.read(a,b-a).hex() for a,b in [(0x1004da90,0x1004daf4),(0x1004d2d0,0x1004d338)]},
                adapters=[hex(a) for a in oracle.adapters],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_weighted_rewards.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Original weighted rewards:',len(examples),'draws,',len(eras),'era values',flush=True)


if __name__=='__main__':main()
