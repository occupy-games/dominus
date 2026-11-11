"""Run original map field reads/writes and house resampling on those bytes."""
import json
import struct

from tools.house_base_stats import extract as base_content
from tools.house_environment import extract
from tools.native_house_surroundings_oracle import SurroundingsOracle, pool
from tools.native_influence_oracle import morton
from tools.native_scenery_oracle import ROOT


TABLE = 0x10a80478
FLAGS = 0x10a78478
NOTIFICATIONS = 0x10a88478


class MapFieldsOracle(SurroundingsOracle):
    def configure_fields(self):
        self.cpu.mem_write(FLAGS, bytes(8 * 1024 * 4))
        self.cpu.mem_write(TABLE, bytes(8 * 1024 * 4))
        self.allocation = self.GRIDS + 0x200000
        self.adapters.update({
            0x10353740: self.allocate,
            0x1035f180: self.zero,
            0x10179af0: lambda: self.return_integer(),  # Out-of-map logging.
        })
        del self.adapters[0x100cf550]
        del self.adapters[0x100cf4b0]
        for address in [0x10353740, 0x1035f180, 0x10179af0]:
            self.handles.append(self.cpu.hook_add(self.hook_kind, self.hook, begin=address, end=address))
        self.reset_notifications(0)

    def allocate(self):
        size, = self.arguments(1)
        if size != 1024 or self.allocation + size > self.GRIDS + 0x400000:
            raise ValueError('Unexpected field allocation')
        address = self.allocation
        self.allocation += size
        self.return_integer(address)

    def zero(self):
        address, value, length = self.arguments(3)
        assert value == 0 and length == 1024
        self.cpu.mem_write(address, bytes(length))
        self.return_integer(address)

    def reset_notifications(self, serial):
        self.queue = self.SCRATCH + 0xa000
        cells = self.queue + 12
        self.cpu.mem_write(self.queue, struct.pack('<III', cells, cells, cells + 128 * 4))
        self.set_integer(NOTIFICATIONS, self.queue)
        self.set_integer(NOTIFICATIONS + 4, serial)

    @staticmethod
    def tile(x, z):
        return (((x & 0xffffffff) >> 5) + (z & 0xffffffe0)) & 0xffffffff

    def write(self, op):
        kind, x, z, value = op['kind'], op['x'], op['z'], op['value']
        tile = self.tile(x, z)
        if tile < 1024:
            self.set_integer(FLAGS + 4 * (kind * 1024 + tile), int(op.get('protected', False)))
        bits, = struct.unpack('<I', struct.pack('<f', value))
        self.call(0x100cfd10 if op.get('checked', False) else 0x100cfe30, [kind, x, z, bits])

    def observations(self, probes):
        reads = []
        for kind, x, z in probes:
            value = self.call(0x100cf4b0, [x, z], floating=True) if kind == -1 else self.call(0x100cf550, [kind, x, z], floating=True)
            reads.append(value)
        begin, end, _ = struct.unpack('<III', self.cpu.mem_read(self.queue, 12))
        cells = [list(struct.unpack('<2H', self.cpu.mem_read(i, 4))) for i in range(begin, end, 4)]
        layers = {}
        for kind in range(8):
            tiles = [tile for tile in range(1024) if self.integer(TABLE + 4 * (kind * 1024 + tile))]
            if tiles:
                layers[str(kind)] = tiles
        return dict(reads=reads, serial=self.integer(NOTIFICATIONS + 4), cells=cells, layers=layers)

    def raw_set(self, kind, x, z, byte):
        tile = self.tile(x, z)
        address = TABLE + 4 * (kind * 1024 + tile)
        buffer = self.integer(address)
        if not buffer:
            buffer = self.allocation
            self.allocation += 1024
            self.cpu.mem_write(buffer, bytes(1024))
            self.set_integer(address, buffer)
        self.cpu.mem_write(buffer + morton(x & 31, z & 31), bytes([byte]))


def main():
    content = extract()
    root = ROOT / 'game/assets/original/campaign'
    base = base_content()
    houses = json.loads((root / 'house-rules.json').read_text())
    timing = json.loads((root / 'house-terrain-frame.json').read_text())
    shrine = json.loads((root / 'temple-effects.json').read_text())
    oracle = MapFieldsOracle((ROOT / 'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_surroundings(base, houses, timing, shrine)
    oracle.configure_fields()
    serial = 0xfffffff9
    oracle.reset_notifications(serial)
    probes = [
        [1, 31, 31], [1, 32, 31], [1, 31, 32], [1, 32, 32],
        [2, 32, 32], [3, 32, 32], [-1, 32, 32], [-1, 31, 31],
        [1, 1024, 0], [1, 0, 32], [1, -1, 0], [1, 0, 1024],
        [5, 15, 16], [4, 8, 9], [6, 9, 8], [2, 33, 32], [3, 33, 32], [-1, 33, 32],
    ]
    stages = [
        [dict(kind=1, x=x, z=z, value=v) for x, z, v in [(31, 31, .5), (32, 31, .5078125), (31, 32, -.01), (32, 32, 2.)]],
        [dict(kind=kind, x=32, z=32, value=v) for kind, v in [(2, .25), (3, 1.5)]],
        [dict(kind=2, x=32, z=32, value=1.75), dict(kind=2, x=31, z=31, value=.75)],
        [dict(kind=1, x=x, z=z, value=1.) for x, z in [(1024, 0), (-1, 0), (0, 1024)]],
        [dict(kind=1, x=31, z=31, value=1., checked=True, protected=True),
         dict(kind=5, x=15, z=16, value=1., checked=False, protected=True),
         dict(kind=1, x=32, z=31, value=1., checked=True, protected=False)],
        [dict(kind=kind, x=x, z=z, value=v) for kind, x, z, v in [(4, 8, 9, 1.), (6, 9, 8, 1.), (2, 33, 32, 1e25), (3, 33, 32, 1.5)]],
        [dict(kind=1 + i % 3, x=i % 3, z=i % 7, value=(i % 9) / 8) for i in range(140)],
    ]
    sequence = []
    for writes in stages:
        for op in writes:
            oracle.write(op)
        sequence.append(dict(writes=writes, expected=oracle.observations(probes)))

    # Fill three small source-map neighborhoods with asymmetric values so
    # a swapped coordinate or a threshold error changes a house's result.
    oracle.cpu.mem_write(TABLE, bytes(8 * 1024 * 4))
    tiles = []
    for x, z in [(0, 1), (1, 1), (0, 2), (2, 1), (3, 0), (4, 2), (3, 1), (16, 4)]:
        byte = 65 if (x + z) % 2 else 64
        oracle.raw_set(1, x, z, byte)
        tiles.append([1, x, z, byte])
    current = pool()
    current['slots']['3']['position'] = [0.25, 1.25, 6.0]
    surroundings = dict(area=[1., 1., 7.0], objects={}, phase=0, radii={'18': 2., '6': 2.75, '12': 1.}, records=[])
    expected = oracle.run_refresh(surroundings, current)['pool']
    fixture = dict(executable_sha256=content['executable_sha256'], serial=serial, probes=probes,
                   sequence=sequence, surroundings=dict(surroundings, initial=current, bytes=tiles, expected=expected),
                   native_routines=dict(content['field_routines'], **content['surroundings_routines']),
                   adapters=[hex(address) for address in sorted(oracle.adapters)])
    path = ROOT / 'game/tests/fixtures/source_map_fields.json'
    path.write_text(json.dumps(fixture, separators=(',', ':')) + '\n')
    print('Original map fields:', len(sequence), 'write stages,', len(probes), 'probes per stage, and house refresh')


if __name__ == '__main__':
    main()
