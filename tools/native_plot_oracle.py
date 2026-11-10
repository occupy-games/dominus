"""Execute the original flat-plot masks with supplied terrain and scenery.

Offline research only. This uses the optional native scenery oracle's bounded
x86 emulator; it never starts the original source, a renderer, or host OS imports.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from tools.native_scenery_oracle import Oracle, ROOT


def scenery_cells(payload,remove_first=False):
    if len(payload)<12 or payload[:8]!=b'DSCN\x01\0\0\0': raise ValueError('Unknown original scenery layout')
    count = struct.unpack_from('<I',payload,8)[0]
    if len(payload)!=12+count*28: raise ValueError('Truncated original scenery layout')
    result=[]
    for root,x,z,height,rotation,origin,kind,authored,reserved in struct.iter_unpack('<IffffIBBH',payload[12:]):
        if reserved or kind>26: raise ValueError('Invalid original scenery record')
        if remove_first and authored and kind==25 and root==123*1024+161: continue
        size=2 if kind>=20 else 1
        result.extend(origin+dx+dz*1024 for dz in range(size) for dx in range(size))
    return result


class PlotOracle(Oracle):
    FLAT = 0x10f4e858
    SCENERY = 0x10f6e8d8
    DIRTY = 0x10f6e858
    SIZES = 0x10f8e8d8

    def configure_plots(self, terrain, occupied, tiles):
        self.configure(terrain, bytes(len(terrain)), bytes(len(terrain)), [])
        self.size_tiles = {}
        for cell in occupied:
            pointer = self.SCENERY+(cell//32)*4
            self.set_integer(pointer, self.integer(pointer) | (1 << (cell%32)))
        for x,z in tiles:
            pointer = self.DIRTY+z*4
            self.set_integer(pointer, self.integer(pointer) | (1 << x))
        self.adapters[0x1025d510] = self.write_size
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.hook,begin=0x1025d510,end=0x1025d510))

    def write_size(self):
        if self.cpu.reg_read(self.regs.UC_X86_REG_ECX)!=self.SIZES:
            raise ValueError('Unexpected original plot-size field')
        cell,value = self.arguments(2)
        x,z = cell%1024,cell//1024
        tile = (z//32)*32+x//32
        if tile not in self.size_tiles:
            pointer = self.GRIDS+len(self.size_tiles)*1024
            self.size_tiles[tile] = pointer
            self.set_integer(self.SIZES+tile*4,pointer)
        self.cpu.mem_write(self.size_tiles[tile]+(z%32)*32+x%32,bytes([value]))
        self.return_integer(pop=8)

    def size_at(self,x,z):
        pointer = self.integer(self.SIZES+((z//32)*32+x//32)*4)
        return self.cpu.mem_read(pointer+(z%32)*32+x%32,1)[0] if pointer else 0

    def masks(self):
        self.call(0x1025e210,limit=100000000)
        self.call(0x1025e5e0,limit=100000000)

    def query(self,origin,size,center,radius):
        pointer = self.SCRATCH+0x2000
        self.cpu.mem_write(pointer,struct.pack('<BB2xfff',1,1,*center,radius))
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,pointer)
        args = struct.unpack('<III',struct.pack('<fff',origin[0]+size*.5,origin[1]+size*.5,size*.5))
        return bool(self.call(0x1012d990,args)&255)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scenery',type=Path,default=ROOT/'game/assets/original/campaign/homeworld6-scenery.bin')
    parser.add_argument('--output',type=Path,default=ROOT/'build/native-homeworld6-plots.json')
    parser.add_argument('--fixture',type=Path)
    args = parser.parse_args()
    raw = (ROOT/'data/godus2_4/godus.s86').read_bytes()
    terrain = (ROOT/'game/assets/original/campaign/homeworld6-terrain.bin').read_bytes()
    scenery = args.scenery.read_bytes()
    metadata = json.loads(args.scenery.with_suffix('.json').read_text())
    if metadata['executable_sha256']!=hashlib.sha256(raw).hexdigest() or metadata['sha256']!=hashlib.sha256(scenery).hexdigest():
        raise ValueError('Scenery executable mismatch')
    occupied = scenery_cells(scenery,True)
    oracle = PlotOracle(raw)
    # A halo covers the 64-cell lookahead of the native 32-cell size tiles.
    tiles = [(x,z) for z in range(2,6) for x in range(3,7)]
    oracle.configure_plots(terrain,occupied,tiles)
    oracle.masks()
    samples = [{'x':x,'z':z,'size':oracle.size_at(x,z)} for z in range(96,160) for x in range(128,192)]
    result = {'executable_sha256':hashlib.sha256(raw).hexdigest(),
              'terrain_sha256':hashlib.sha256(terrain).hexdigest(),
              'scenery_sha256':hashlib.sha256(scenery).hexdigest(),
              'removed_authored_rock':[161,123], 'dirty_tiles':tiles,
              'native_routines':{hex(start):oracle.image.read(start,end-start).hex()
                                 for start,end in [(0x1025e210,0x1025e3cd),(0x1025e5e0,0x1025ea60),
                                                   (0x1012d990,0x1012da73),(0x10239abe,0x10239b02),
                                                   (0x1024358e,0x102435ba)]},
              'adapters':[hex(address) for address in sorted(oracle.touched)],
              'samples':samples,
              'scope':'Original flat/clear size fields only; not complete plot allocation, claims or construction.'}
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    if args.fixture:
        fixture = {key:result[key] for key in ['executable_sha256','terrain_sha256','native_routines','scope']}
        fixture.update(scenery_sha256=hashlib.sha256(scenery).hexdigest(),
                       bounds=[128,96,192,160],dirty_tiles=tiles,
                       minimum_raw_height=struct.unpack('<f',oracle.image.read(0x104acfb8,4))[0],
                       max_size=16,cases=[])
        for name,removed,edits in [('initial',False,[]),('cleared',True,[]),('sculpted',True,[[161,120,20]])]:
            changed = bytearray(terrain)
            for x,z,value in edits: changed[z*1024+x]=value
            cells = scenery_cells(scenery,removed)
            check = PlotOracle(raw)
            check.configure_plots(bytes(changed),cells,tiles)
            check.masks()
            capacities = bytes(check.size_at(x,z) for z in range(96,160) for x in range(128,192))
            fixture['cases'].append({'name':name,'removed_rock':removed,'terrain_edits':edits,
                                     'capacities':capacities.hex()})
        fixture['queries']=[]
        for origin,size,center,radius in [([157,121],4,[161,123],1),([156,121],4,[161,123],1),
                                           ([155,121],4,[161,123],1),([159,121],3,[161,123],1),
                                           ([156,120],4,[161,123],1),([158,120],4,[161,123],0)]:
            fixture['queries'].append(dict(origin=origin,size=size,center=center,radius=radius,
                                            intersects=oracle.query(origin,size,center,radius)))
        args.fixture.write_text(json.dumps(fixture,indent=2)+'\n')
    print('Original plot-size mask:',len(samples),'samples;',
          [(s['x'],s['z'],s['size']) for s in samples if 157<=s['x']<=162 and 120<=s['z']<=123])


if __name__=='__main__': main()
