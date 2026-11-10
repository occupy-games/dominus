"""Bounded original tree dirty refresh, occupancy bits and null-growth scale helper.

Runs supplied CPU instructions against controlled in-memory scenery and terrain.
No original entrypoint, renderer, OS imports, network or audio is started.
"""
import argparse
import json
import struct

from tools.native_rock_motion_oracle import MotionOracle
from tools.native_scenery_oracle import ROOT
from tools.tree_response import extract


class TreeOracle(MotionOracle):
    def configure_trees(self,objects,config):
        self.configure_motion(objects,1.)
        for key,address in [('vertical_scale',0x105d91fc),('encouragement_scale',0x105d9200),
                            ('duration',0x105d920c),('minimum_scale',0x105d9210)]: self.set_float(address,config[key])
        for i,item in enumerate(objects):
            p=self.POOL+i*0xec
            self.set_integer(p+0x34,0)
            self.set_integer(p+0x4c,1)
            self.set_float(p+0x40,1.)
            # Native initial constructor: no growth record, no encouragement.
            self.set_integer(p+0xb0,0)
            self.set_float(p+0x9c,0.)
            self.set_integer(0x10fcbc38,1)
            self.set_integer(0x10fcbc3c,1)
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,p)
            self.call(0x10156ae0)

    def tree_snapshot(self):
        result=[]
        for i,item in enumerate(self.objects):
            p=self.POOL+i*0xec
            cell=item['cells'][0]
            x,z=cell%1024,cell//1024
            occupied=bool(self.integer(0x10f6e8d8+z*128+(x//32)*4)&(1<<(x%32)))
            tile=(z//32)*32+x//32
            identity=struct.unpack('<H',self.cpu.mem_read(self.grids[tile]+((z%32)*32+x%32)*2,2))[0]
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,p)
            scale=self.call(0x10155f20,floating=True)
            result.append({'enabled':bool(self.integer(p+0x4c)),'changed_ms':self.float(p+0x44),
                           'height':self.float(p+0x30),'occupied':occupied,'identity':identity,'scale':scale})
        return result


def object_at(x,z):
    return {'x':x,'z':z,'height':6.,'cells':[int(z)*1024+int(x)]}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=str,default=str(ROOT/'game/tests/fixtures/source_tree_response.json'))
    args=parser.parse_args()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    config=extract()
    objects=[object_at(161.5,123.5)]
    steps=lambda levels:[{'raw':level,'now':10.+i*.1,'refresh':True} for i,level in enumerate(levels)]
    cases=[{'name':'unchanged','objects':objects,'steps':steps([20,20])},
           {'name':'raise_restore','objects':objects,'steps':steps([21,21,20,20])},
           {'name':'lower_restore','objects':objects,'steps':steps([19,18,20])},
           {'name':'zero_reenable','objects':objects,'steps':steps([21,0,0,20])},
           {'name':'outside_dirty','objects':objects,'tiles':[[4,3]],'steps':steps([21,20])},
           {'name':'no_refresh','objects':objects,'steps':[{'raw':21,'now':10.,'refresh':False}]},
           {'name':'two_tiles','objects':objects+[object_at(193.5,123.5)],'steps':steps([21,20])}]
    for case in cases:
        o=TreeOracle(raw)
        o.configure_trees(case['objects'],config)
        tiles=case.setdefault('tiles',sorted({(int(i['x'])//32,int(i['z'])//32) for i in case['objects']}))
        case['states']=[]
        for step in case['steps']:
            o.terrain=bytes([step['raw']])*(1024*1024)
            o.set_float(0x10d9b620,step['now'])
            if step['refresh']: o.refresh(tiles)
            case['states'].append(o.tree_snapshot())
    scales=[]
    for enabled in [False,True]:
        for base in [0.,.5,1.]:
            for encouragement in [0.,.5,1.]:
                for elapsed in [0.,.1,.18,.2,.3,.36,.5,.6,1.]:
                    p=o.POOL
                    o.set_integer(p+0x4c,int(enabled))
                    o.set_float(p+0x40,base)
                    o.set_float(p+0x9c,encouragement)
                    o.set_float(p+0x44,10000.)
                    o.set_float(0x10d9b620,10.+elapsed)
                    o.cpu.reg_write(o.regs.UC_X86_REG_ECX,p)
                    scales.append({'enabled':enabled,'base':base,'encouragement':encouragement,
                                   'now':o.float(0x10d9b620),'changed_ms':10000.,'scale':o.call(0x10155f20,floating=True)})
    result={'configuration':config,'cases':cases,'scale_cases':scales,'adapters':[hex(a) for a in sorted(o.adapters)],
            'scope':'Controlled initially dry trees, native dirty scan, native occupancy bit loops and scale helper with null growth record. Runtime density regeneration, planted growth records and submerged initial objects are outside this comparison.'}
    (ROOT/args.output).write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Original tree response:',len(cases),'terrain cases,',len(scales),'scale cases')


if __name__=='__main__':main()
