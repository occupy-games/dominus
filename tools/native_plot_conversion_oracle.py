"""Observe original plot-to-building creation and immediate plot-pool release.

Original factory selection/placement, matching-house rotation rule, ordered
footprint removal, pool release and dirty marking run. House allocation and
construction are explicit adapters: this captures the constructor request, not
the full building object or follower job. No game entrypoint or OS service runs.
"""
import argparse
import hashlib
import json
import struct

from tools.house_selection import extract
from tools.native_house_selection_oracle import SelectionOracle
from tools.native_plot_registry_oracle import RegistryOracle
from tools.native_scenery_oracle import ROOT


class ConversionOracle(RegistryOracle, SelectionOracle):
    HOUSE_POOL = 0x31000000

    def configure_conversion(self,case):
        self.case=case
        plot=dict(id=0,x=158,z=120,size=4,claimed=False)
        plot.update(case.get('plot',{}))
        self.configure_registry(dict(plots=[plot],minimum=4,maximum=4))
        self.plot=plot
        previous=dict(self.adapters)
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[]
        self.configure_selection(extract())
        selection_adapters=dict(self.adapters)
        for handle in self.handles:self.cpu.hook_del(handle)
        self.adapters=previous|selection_adapters
        self.profile(dict(unlocks=case.get('unlocks',['PlotsAppear']),biome_locked=case.get('biome_locked',True)))
        self.set_float(0x105b2d08,25)
        self.set_float(0x105b2d0c,36)
        self.set_float(self.POOL+0x14,plot.get('rotation',0.))
        offset=plot.get('offset',[0.,0.])
        self.set_float(self.POOL+0x34,offset[0])
        self.set_float(self.POOL+0x38,offset[1])
        self.set_integer(0x10fcd474,self.HOUSE_POOL)
        houses=case.get('houses',[])
        for i,house in enumerate(houses):
            pointer=self.HOUSE_POOL+i*0x2d8
            self.cpu.mem_write(pointer,bytes(0x2d8))
            self.cpu.mem_write(pointer,struct.pack('<HH',i-1 if i else 0xffff,0xffff))
            self.set_integer(pointer+0x264,house.get('index',18))
            self.set_integer(pointer+0x88,house.get('owner',0)<<29)
        self.house=self.HOUSE_POOL+len(houses)*0x2d8
        self.cpu.mem_write(self.house,bytes(0x2d8))
        self.cpu.mem_write(0x10fcd47e,struct.pack('<H',len(houses)-1 if houses else 0xffff))
        self.request=None
        self.random_calls=0
        self.ground_queries=[]
        self.cpu.mem_write(0x10f6e858,bytes(128))
        self.adapters.update({
            0x100441c0:self.allocate_house,
            0x1025c150:self.ground,
            0x1035f7f0:self.random_word,
            0x100bc660:self.constructor,
            0x10124cc0:lambda:self.return_integer(), # settlement attachment
            0x1035fde0:lambda:self.return_integer(), # diagnostic formatting
            0x10010fe0:lambda:self.return_integer(), # analytics counters
        })
        # Run the actual stack-cookie check. It preserves EAX, where the factory
        # has already placed its result; a generic integer stub would erase it.
        self.adapters.pop(0x1035f830,None)
        # The native footprint erasure and free-list manipulation still run.
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def allocate_house(self):
        if self.case.get('allocation_failed',False):self.return_integer();return
        count=len(self.case.get('houses',[]))
        self.cpu.mem_write(self.house,struct.pack('<HH',count-1 if count else 0xffff,0xffff))
        self.cpu.mem_write(0x10fcd47e,struct.pack('<H',count))
        self.return_integer(self.house)

    def ground(self):
        x,z,flags=self.arguments(3)
        if flags!=0:raise ValueError('Unexpected native conversion ground flags')
        self.ground_queries.append(list(struct.unpack('<ff',struct.pack('<II',x,z))))
        self.return_float(self.case.get('ground',6.))

    def random_word(self):
        self.random_calls+=1
        self.return_integer(self.case.get('random_word',0))

    def constructor(self):
        args=self.arguments(13)
        pointer=self.cpu.reg_read(self.regs.UC_X86_REG_ECX)
        self.request=dict(position=list(struct.unpack('<4f',struct.pack('<4I',*args[:4]))),
                          index=args[4],owner=args[5],extra=args[6],kind=args[7],special=args[8],
                          unknown_a=args[9],unknown_b=args[10],configuration=args[11],reuse=bool(args[12]))
        self.set_integer(pointer+0xec,0xffffffff) # No settlement membership in this adapter.
        self.set_integer(pointer+0x264,args[4])
        self.set_integer(pointer+0x154,self.plot['size'])
        self.return_integer(pop=52)

    def convert(self):
        reuse=bool(self.case.get('reuse',False))
        target=self.HOUSE_POOL if reuse else 0
        result=self.call(0x10044cb0,[self.POOL,self.case.get('owner',0),0xffffffff,
                                  self.case.get('kind',0),int(self.case.get('special',False)),target],limit=4000000)
        return dict(created=bool(result),request=self.request,random_calls=self.random_calls,
                    ground_queries=self.ground_queries,registry=self.snapshot(),
                    dirty=[i for i in range(1024) if self.integer(0x10f6e858+(i//32)*4)&(1<<(i%32))])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_plot_conversion.json'))
    args=parser.parse_args()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    cases=[dict(name='first'),dict(name='allocation_failed',allocation_failed=True),
           dict(name='offset',plot=dict(offset=[.25,-.375],rotation=.4)),
           dict(name='height_boundary',ground=7.5,unlocks=['PlotsAppear','Mid_Rank_1']),
           dict(name='other_owner',owner=1,houses=[dict(owner=0)]*4),
           dict(name='reuse',reuse=True,houses=[{}]),
           dict(name='farm',kind=1,special=True),dict(name='mine',kind=2,special=True)]
    for count in [1,2,3,4]:
        for word in ([0,8191,8192,16383,16384,24575,24576,32767] if count==3 else [16384]):
            cases.append(dict(name=f'matching_{count}_{word}',houses=[{}]*count,random_word=word))
    cases.append(dict(name='different_types',houses=[dict(index=19)]*4,random_word=16384))
    oracle=ConversionOracle(raw)
    for case in cases:
        oracle.configure_conversion(case)
        case['expected']=oracle.convert()
    source=extract()
    result={key:source[key] for key in ['source_sha256','table_sha256','executable_sha256']}
    result.update(cases=cases,native_routines={hex(a):oracle.image.read(a,b-a).hex() for a,b in [
        (0x10044c30,0x10044ca6),(0x10044cb0,0x10044f97),(0x10237660,0x102376e8),
        (0x10044110,0x100441b8),(0x10235750,0x1023576b),(0x1035f830,0x1035f83f)]},
        constants={hex(a):dict(bytes=oracle.image.read(a,8).hex(),value=struct.unpack('<d',oracle.image.read(a,8))[0])
                   for a in [0x104aaed0,0x104a0c68]},adapters=[hex(a) for a in sorted(oracle.adapters)],
        scope='Original plot-to-building factory protocol: house selection, offset placement/height, matching-house rotation, immediate footprint and pool removal. Constructor/allocation, ground, random word, settlement attachment and diagnostics are adapters. Not a complete building constructor, follower decision/dispatch or campaign construction playthrough.')
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original plot conversion:',len(cases),'cases;',[(c['name'],c['expected']['request'],c['expected']['random_calls']) for c in cases[:6]])


if __name__=='__main__':main()
