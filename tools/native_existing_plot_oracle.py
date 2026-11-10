"""Capture original existing-plot cell/ownership validation over controlled fields.

Executes native 0x102363c0, 0x10236510 and 0x10236610. The original
ownership-tree lookup and blight predicate run too; no renderer/OS/game entrypoint.
This is not the full plot resize/merge loop or a campaign playthrough.
"""
import argparse
import hashlib
import itertools
import json
import struct

from tools.native_plot_allocation_oracle import AllocationOracle
from tools.native_scenery_oracle import ROOT


class ExistingPlotOracle(AllocationOracle):
    def configure_existing(self):
        self.configure_allocation(bytes([20])*(1024*1024),[],bytes(1024*1024),[],
                                  {'loc2Start':25,'loc3Start':36,'biome1Index':17,'biome2Index':19,'biome3Index':18},
                                  [0,0,1024,1024],[[4,4],[0,0],[0,0]])
        self.adapters[0x100cf550]=self.field
        for handle in self.handles: self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.plot=self.POOL
        self.other=self.POOL+0x74
        self.set_integer(self.plot+4,4)
        self.set_float(self.plot+8,160.)
        self.set_float(self.plot+12,120.)
        self.set_float(self.plot+16,6.)
        self.set_integer(self.other+4,4)
        self.blight={}

    def field(self):
        kind,x,z=self.arguments(3)
        if kind!=5: raise ValueError('Unexpected native plot field')
        self.return_float(self.blight.get((x,z),0.))

    def owners(self,entries):
        self.cpu.mem_write(self.head,bytes(32))
        self.nodes={}
        def branch(items):
            if not items:return 0
            half=len(items)//2
            key,value=items[half]
            pointer=self.GRIDS+0x200000+key%1024*32+(key//1024-110)*32768
            self.nodes[key]=pointer
            self.cpu.mem_write(pointer,bytes(32))
            self.set_integer(pointer+0x10,key)
            self.set_integer(pointer+0x14,value)
            self.set_integer(pointer+8,branch(items[:half]))
            self.set_integer(pointer+12,branch(items[half+1:]))
            return pointer
        self.set_integer(self.head+4,branch(sorted(entries.items())))

    def bit(self,address,x,z,value):
        pointer=address+z*128+(x//32)*4
        mask=1<<(x%32)
        self.set_integer(pointer,(self.integer(pointer)&~mask)|(mask if value else 0))

    def probe(self,case):
        x,z=case['cell']
        data=bytearray(1024*1024)
        data[120*1024+160]=case['origin_byte']
        if (x,z)!=(160,120): data[z*1024+x]=case['cell_byte']
        self.plotrot=bytes(data)
        self.blight={(x,z):case['blight']}
        self.set_integer(0x110a4978,case['biome_mask'])
        self.set_integer(self.other+0x4c,1 if case['owner']=='claimed' else 0)
        self.set_integer(self.plot+0x4c,1 if case.get('self_claimed') else 0)
        owner={'none':0,'self':self.plot,'unclaimed':self.other,'claimed':self.other}[case['owner']]
        entries={pz*1024+px:self.plot for pz in range(120,124) for px in range(160,164)}
        if owner: entries[z*1024+x]=owner
        else: entries.pop(z*1024+x,None)
        self.owners(entries)
        self.bit(self.FLAT,x,z,case['flat'])
        self.bit(self.SCENERY,x,z,case['scenery'])
        self.bit(0x10f2e858,x,z,case['blocked'])
        result={}
        for name,address,args in [('cell',0x102363c0,[x,z]),('whole',0x10236510,[]),('interior',0x10236610,[])]:
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.plot)
            result[name]=bool(self.call(address,args))
        # Reset individual masks for the next independent input.
        self.bit(self.FLAT,x,z,True)
        self.bit(self.SCENERY,x,z,False)
        self.bit(0x10f2e858,x,z,False)
        return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_existing_plots.json'))
    args=parser.parse_args()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    oracle=ExistingPlotOracle(raw)
    oracle.configure_existing()
    cases=[]
    # Exact origin versus border/interior/candidate behavior, ownership and
    # rotation-byte/blight gates. All terrain quads are otherwise level/dry.
    for cell,owner,flat,scenery,blocked in itertools.product([[160,120],[161,121],[159,121]],['none','self','unclaimed','claimed'],[False,True],[False,True],[False,True]):
        cases.append(dict(cell=cell,owner=owner,flat=flat,scenery=scenery,blocked=blocked,origin_byte=0,cell_byte=0,blight=0.,biome_mask=1))
    for cell,origin,byte,blight,biome in itertools.product([[160,120],[161,121],[159,121]],[0,64,65,127,128],[0,18,19,20,21,22],[0.,1.],[0,1]):
        cases.append(dict(cell=cell,owner='self',flat=True,scenery=False,blocked=False,origin_byte=origin,cell_byte=byte,blight=blight,biome_mask=biome))
    for case in cases: case['expected']=oracle.probe(case)
    result={'executable_sha256':hashlib.sha256(raw).hexdigest(),'plot':{'id':1,'x':160.,'z':120.,'size':4,'height':6.},
            'cases':cases,'native_routines':{hex(a):oracle.image.read(a,b-a).hex() for a,b in [
                (0x10236370,0x1023671a),(0x101454a0,0x1014550b),(0x102358b0,0x102358de)]},
            'adapters':[hex(a) for a in sorted(oracle.touched)],
            'scope':'Native existing-plot cell predicate, full ownership validation and interior ownership validation with controlled flat/scenery/blocked/rotation/blight/biome fields. Not resize/merge decisions, claims, AOI initialization or construction.'}
    (ROOT/args.output).write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Original existing plot validation:',len(cases),'cases')


if __name__=='__main__':main()
