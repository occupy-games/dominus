"""Observe original influence-circle rasterization and plot/power eligibility.

The original circle registry, raster, byte quantization, Morton lookup and gates
execute. Only heap allocation/zeroing are host storage adapters. No entrypoint,
renderer, audio or OS import executes; this optional oracle is offline only.
"""
import argparse
import hashlib
import json
import struct

from tools.native_scenery_oracle import Oracle, ROOT
from tools.current_cards import decode_archive, rows


def morton(x, z):
    return sum(((x >> bit)&1) << (bit*2) | ((z >> bit)&1) << (bit*2+1) for bit in range(5))


class InfluenceOracle(Oracle):
    def configure_influence(self):
        self.next_allocation = self.GRIDS
        self.cpu.mem_write(0x10a80478, bytes(8*1024*4))
        self.cpu.mem_write(0x10a88480, bytes(0x2104))
        self.adapters = {0x10353740:self.allocate, 0x1035f180:self.zero}
        self.handles = [self.cpu.hook_add(self.hook_kind, self.hook, begin=a, end=a) for a in self.adapters]

    def allocate(self):
        size, = self.arguments(1)
        if size > 4096: raise ValueError('Unknown influence allocation size')
        pointer = self.next_allocation
        self.next_allocation += (size+15)&~15
        if self.next_allocation > self.GRIDS+0x400000: raise ValueError('Influence storage budget exceeded')
        self.cpu.mem_write(pointer, bytes(size))
        self.return_integer(pointer)

    def zero(self):
        pointer, value, size = self.arguments(3)
        if size > 4096: raise ValueError('Unknown influence zeroing size')
        self.cpu.mem_write(pointer, bytes([value&255])*size)
        self.return_integer(pointer)

    def circle(self, command):
        bits = struct.unpack('<III', struct.pack('<fff', command['x'], command['z'], command['radius']))
        identity = int(command['id'])
        return self.call(0x100d0a10, [identity&0xffffffff, identity>>32, *bits, int(command.get('powers_only', False)),
                                     int(command.get('maximum', True)), int(command.get('force', False))])

    def byte(self, field, x, z):
        pointer = self.integer(0x10a80478+4*(field*1024+(z//32)*32+x//32))
        return self.cpu.mem_read(pointer+morton(x%32,z%32), 1)[0] if pointer else 0

    def capture(self, bounds):
        x0,z0,x1,z1 = bounds
        result = {}
        for field in [4,6]:
            result[str(field)] = bytes(self.byte(field,x,z) for z in range(z0,z1) for x in range(x0,x1)).hex()
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default=str(ROOT/'game/tests/fixtures/source_influence.json'))
    args = parser.parse_args()
    raw = (ROOT/'data/godus2_4/godus.s86').read_bytes()
    cases = []
    for radius in [0., .5, 2., 2.25, 4., 12., 22.]:
        cases.append(dict(name='radius_'+str(radius), bounds=[130,88,192,150],
                          commands=[dict(id=1,x=161.,z=119.,radius=radius)]))
    cases += [dict(name='fractional',bounds=[146,105,178,137],commands=[dict(id=1,x=161.375,z=119.125,radius=12.25)]),
              dict(name='nonbinary',bounds=[146,105,178,137],commands=[dict(id=1,x=161.1,z=119.3,radius=12.1)]),
              dict(name='map_edge',bounds=[0,0,16,16],commands=[dict(id=1,x=.25,z=.125,radius=12.)]),
              dict(name='power_area',bounds=[146,105,178,137],commands=[dict(id=1,x=161.,z=119.,radius=12.,powers_only=True)]),
              dict(name='overlap',bounds=[146,105,178,137],commands=[dict(id=1,x=157.,z=119.,radius=9.),dict(id=2,x=166.,z=119.,radius=9.)]),
              dict(name='unchanged_identity',bounds=[146,105,178,137],commands=[dict(id=1,x=161.,z=119.,radius=12.)]*2),
              dict(name='forced_identity',bounds=[146,105,178,137],commands=[dict(id=1,x=161.,z=119.,radius=12.),dict(id=1,x=161.,z=119.,radius=12.,force=True)]),
              dict(name='erase_rectangle',bounds=[146,105,178,137],commands=[dict(id=1,x=157.,z=119.,radius=9.),dict(id=2,x=166.,z=119.,radius=9.,maximum=False)]),
              dict(name='large_identity',bounds=[146,105,178,137],commands=[
                  dict(id=str(value),x=161.,z=119.,radius=12.) for value in [0x1aaaaaa00000011,0x1aaaaaa00000011,0x1aaaaab00000011]])]
    archive = (ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    area_rows = rows(decode_archive(archive),'initialworldsetup6/influence_areas.csv')
    initial = [dict(id=str(0x1aaaaaa00000000+index),x=float(row[2]),z=float(row[3]),radius=float(row[4]),powers_only=bool(int(row[6])))
               for index,row in enumerate(area_rows[1:]) if len(row)>6 and row[2] and int(row[5])]
    cases.append(dict(name='source_initial_areas',bounds=[100,30,200,165],commands=initial))
    oracle = None
    for case in cases:
        oracle = InfluenceOracle(raw)
        oracle.configure_influence()
        case['states'] = []
        for command in case['commands']:
            changed = oracle.circle(command)
            case['states'].append(dict(changed=bool(changed),fields=oracle.capture(case['bounds'])))
        print('Original influence:',case['name'],flush=True)
    gates = []
    # Execute the actual plot/power predicate with original quantized fields.
    for byte4 in [0,31,32,33,127,128,255]:
        for byte6 in [0,31,32,33,127,128,255]:
            for field, byte in [(4,byte4),(6,byte6)]:
                address = oracle.GRIDS+0x300000+field*1024
                oracle.set_integer(0x10a80478+4*(field*1024+3*32+5),address)
                oracle.cpu.mem_write(address+morton(0,24),bytes([byte]))
            gates.append(dict(fields=[byte4,byte6],build=bool(oracle.call(0x10257570,[160,120,0])&255),
                              power=bool(oracle.call(0x10257570,[160,120,1])&255)))
    result = dict(executable_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=hashlib.sha256(archive).hexdigest(),
                  area_table_sha256=hashlib.sha256(decode_archive(archive)['initialworldsetup6/influence_areas.csv']).hexdigest(),cases=cases,gates=gates,
                  constants={hex(a):dict(bytes=oracle.image.read(a,n).hex(),value=struct.unpack('<d' if n==8 else '<f',oracle.image.read(a,n))[0])
                             for a,n in [(0x104a0c30,8),(0x104a0d00,8),(0x104acfa8,8),(0x104acff0,8),(0x104bd430,8),(0x1060f5e0,4)]},
                  native_routines={hex(a):oracle.image.read(a,b-a).hex() for a,b in [
                      (0x100d0a10,0x100d0d3c),(0x100cfe30,0x100cff14),(0x100cf550,0x100cf5ae),
                      (0x100cfb40,0x100cfc2c),(0x10257570,0x10257602)]},
                  adapters=[hex(a) for a in sorted(oracle.adapters)],
                  scope='Original registered-circle raster, byte storage, native lookup and plot/power gates over explicit circles. Source campaign area registration/unlocks, transition radii and dynamic building influences are separate.')
    (ROOT/args.output).write_text(json.dumps(result,separators=(',', ':'))+'\n')


if __name__ == '__main__': main()
