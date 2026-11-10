"""Capture original discrete terrain sampling, without starting the original source.

The native four-corner sampler executes unchanged. Only raw grid reads are
adapted; the corner decisions and float boundaries are original CPU code.
"""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import struct

from tools.native_scenery_oracle import Oracle, ROOT


class SampleOracle(Oracle):
    def configure_samples(self,terrain):
        self.configure(terrain,b'',b'',[])

    def sample(self,x,z):
        args=struct.unpack('<II',struct.pack('<ff',x,z))
        return self.call(0x1025b8f0,[*args,0,0,0,0])

    def script_step(self,x,z):
        self.script_arguments=[x,z]
        self.script_output=None
        if 0x10338ead not in self.adapters:
            self.adapters[0x10338ead]=self.lua_number
            self.adapters[0x1033904e]=self.lua_result
            for address in [0x10338ead,0x1033904e]:
                self.handles.append(self.cpu.hook_add(self.hook_kind,self.hook,begin=address,end=address))
        self.call(0x1023f530)
        if self.script_output is None: raise ValueError('Original script query did not return')
        return self.script_output

    def lua_number(self):
        _,index=self.arguments(2)
        self.return_float(self.script_arguments[index-1])

    def lua_result(self):
        _,lo,hi=self.arguments(3)
        self.script_output=struct.unpack('<d',struct.pack('<II',lo,hi))[0]
        self.return_integer()


def predicted(corners,x,z):
    # Independent compact expression derived from the native branches. The
    # tool compares this hypothesis as it captures; fixtures store CPU output.
    a,b,c,d=corners
    if x+z<.5: return a
    if x+1-z<.5: return c
    if 1-x+z<.5: return b
    if 2-x-z<.5: return d
    if x<.5: return sorted([a,b,c])[1] if z<.5 else sorted([c,a,d])[1]
    return sorted([b,a,d])[1] if z<.5 else sorted([d,b,c])[1]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'game/tests/fixtures/source_terrain_samples.json')
    args=parser.parse_args()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    terrain=(ROOT/'game/assets/original/campaign/homeworld6-terrain.bin').read_bytes()
    oracle=SampleOracle(raw)
    oracle.configure_samples(terrain)
    fractions=[0.,.125,.25,.375,.4999,.5,.5001,.625,.75,.875,.9999]
    points=[list(struct.unpack('<ff',struct.pack('<ff',100+x,100+z))) for z in fractions for x in fractions]
    cases=[]
    errors=[]
    for corners in itertools.product([0,19,20,25],repeat=4):
        patch=bytearray(terrain)
        for cell,value in zip([100*1024+100,100*1024+101,101*1024+100,101*1024+101],corners): patch[cell]=value
        oracle.terrain=bytes(patch)
        values=bytes(oracle.sample(*point) for point in points)
        cases.append({'corners':list(corners),'values':values.hex()})
        errors.extend((corners,point,actual,predicted(corners,point[0]-100,point[1]-100)) for point,actual in zip(points,values) if actual!=predicted(corners,point[0]-100,point[1]-100))
    oracle.terrain=terrain
    source_points=[(x+dx,z+dz) for z in range(116,140,3) for x in range(150,173,3) for dx,dz in [(.125,.375),(.5,.5),(.875,.625)]]
    source=[[*point,oracle.sample(*point)] for point in source_points]
    script=[[*point,oracle.script_step(*point)] for point in source_points]
    oracle.terrain=bytes([20])*(1024*1024)
    edges=[[*point,oracle.sample(*point)] for point in [(-1.25,100),(-.25,100),(0,100),(1022.9999,100),(1023,100),(1023.25,100),(1024,100),
                                                      (100,-1.25),(100,-.25),(100,0),(100,1022.9999),(100,1023),(100,1023.25),(100,1024)]]
    result={'executable_sha256':hashlib.sha256(raw).hexdigest(),'terrain_sha256':hashlib.sha256(terrain).hexdigest(),
            'points':points,'cases':cases,'source_samples':source,'script_samples':script,'edge_samples':edges,
            'script_registration':{'address':'0x1060d870','bytes':oracle.image.read(0x1060d870,8).hex()},
            'height_scale':struct.unpack('<d',oracle.image.read(0x104a0c78,8))[0],
            'native_routines':{hex(a):oracle.image.read(a,b-a).hex() for a,b in [(0x1025b8f0,0x1025c11d),(0x1025c150,0x1025c196),(0x1023f530,0x1023f59b)]},
            'adapters':[hex(a) for a in sorted(oracle.touched)],
            'scope':'Discrete default four-corner terrain query, no sculpt overrides or alternate float field; not continuous visual geometry or full scenery refresh.'}
    if errors: raise ValueError('Native sample hypothesis differs: '+str(errors[:12])+'; total '+str(len(errors)))
    args.output.write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Original terrain sampling:',len(cases)*len(points),'corner cases,',len(source),'source samples')


if __name__=='__main__': main()
