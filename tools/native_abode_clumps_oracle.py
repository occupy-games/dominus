"""Run original grouping and fill code with house/stat, allocator and Lua adapters."""
import json
import struct

from tools.abode_clumps import extract
from tools.native_scenery_oracle import ROOT, Oracle


class ClumpOracle(Oracle):
    def configure_clumps(self):
        self.adapters = {0x100b7580: self.stats, 0x10353740: self.allocate_node,
                         0x10146560: self.append_vector, 0x103571c0: self.return_integer,
                         0x1035fde0: self.callback, 0x10339c95: self.return_integer,
                         0x103394c9: self.return_integer}
        self.handles = [self.cpu.hook_add(self.hook_kind, self.hook, begin=a, end=a)
                        for a in self.adapters]

    def stats(self):
        house = self.cpu.reg_read(self.regs.UC_X86_REG_ECX)
        self.return_integer(house + 0x300000)

    def allocate_node(self):
        size, = self.arguments(1)
        if size != 12:
            raise ValueError('Unexpected native clump node size')
        pointer = self.POOL + 0x100000 + self.nodes * 12
        self.nodes += 1
        self.return_integer(pointer)

    def append_vector(self):
        owner = self.cpu.reg_read(self.regs.UC_X86_REG_ECX)
        position, value, _, count, capacity = self.arguments(5)
        if position or count != 1 or capacity != 1:
            raise ValueError('Unexpected initial native vector insertion')
        buffer = self.POOL + 0x120000
        self.set_integer(buffer, self.integer(value))
        for offset, pointer in [(0, buffer), (4, buffer+4), (8, buffer+4096)]:
            self.set_integer(owner+offset, pointer)
        self.return_integer(pop=20)

    def callback(self):
        destination, _, _, handle = self.arguments(4)
        self.selected.append(handle & 0xffffff)
        self.cpu.mem_write(destination, b'callback()\0')
        self.return_integer(10)

    def group(self, case):
        houses = case['houses']
        self.nodes = 0
        self.selected = []
        self.set_integer(0x10fcd474, self.POOL)
        self.cpu.mem_write(0x10fcd47e, struct.pack('<H', len(houses)-1 if houses else 0xffff))
        for index, house in enumerate(houses):
            address = self.POOL + index*0x2d8
            self.cpu.mem_write(address, bytes(0x2d8))
            self.cpu.mem_write(address, struct.pack('<H', index-1 if index else 0xffff))
            self.set_float(address+0xb0, house['x'])
            self.set_float(address+0xb4, house['z'])
            self.set_integer(address+0x134, house.get('state', 1))
            self.set_integer(address+0x300000+0x3c, house.get('type', 2))
        name = self.POOL+0x160000
        self.cpu.mem_write(name, b'callback\0')
        radius, = struct.unpack('<I', struct.pack('<f', case['radius']))
        self.call(0x10246d80, [case.get('type', 2), radius, name,
                               int(case.get('include_unfinished', True)), 0])
        return self.selected.copy()

    def fill(self, stored, maximum):
        self.set_float(self.POOL+0x15c, stored)
        self.set_float(self.POOL+0x300000+0x74, maximum)
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX, self.POOL)
        self.call(0x100b8a30)
        return self.float(self.POOL+0x15c)


def main():
    oracle = ClumpOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_clumps()
    arrangements = [[], [(0, 0)], [(0, 0), (3, 0)], [(0, 0), (2.999, 0)],
                    [(0, 0), (2, 0), (4, 0), (20, 0)],
                    [(0, 0), (10, 0), (2, 0), (12, 0)],
                    [(0, 0), (8, 0), (4, 0), (6, 0), (2, 0)],
                    [(160, 122), (162, 126), (163, 130), (165, 137), (170, 136)]]
    cases = []
    for points in arrangements:
        for radius in [3.0, 5.0]:
            for include in [False, True]:
                for varied in [False, True]:
                    houses = [dict(x=x, z=z, type=1 if varied and i%3==0 else 2,
                                   state=0 if varied and i%2==0 else 1)
                              for i, (x, z) in enumerate(points)]
                    case = dict(houses=houses, radius=radius, include_unfinished=include)
                    case['expected'] = oracle.group(case)
                    cases.append(case)
    fills = [dict(stored=value, maximum=maximum, expected=oracle.fill(value, maximum))
             for value in [0., 10., 20., 25.5] for maximum in [0., 20., 30.25]]
    result = dict(rules=extract(), cases=cases, fills=fills)
    path = ROOT/'build/native-abode-clumps.json'
    path.write_text(json.dumps(result, indent=2)+'\n')
    print('Original abode clumps:', len(cases), 'cases and', len(fills), 'fill cases')


if __name__ == '__main__':
    main()
