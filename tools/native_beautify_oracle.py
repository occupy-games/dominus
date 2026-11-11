"""Compare the original Beautify action after projection onto a map point."""
import json
import struct

from tools.beautify import extract
from tools.house_base_stats import extract as base_content
from tools.native_map_fields_oracle import FLAGS, TABLE, MapFieldsOracle
from tools.native_scenery_oracle import ROOT


class BeautifyOracle(MapFieldsOracle):
    def configure_beautify(self, base, houses, timing, shrine):
        self.configure_surroundings(base, houses, timing, shrine)
        self.configure_fields()
        self.adapters.update({
            0x10261560: self.ray, 0x101450b0: self.ground, 0x1012ec90: lambda: self.return_integer(),
            0x100628c0: self.payment, 0x1025a6f0: self.cell_changed,
            0x1025a780: self.dirty, 0x100444c0: self.refresh_area,
            0x100ec410: lambda: self.return_integer(), 0x1024a650: lambda: self.return_integer(),
            0x1035f830: lambda: self.return_integer(self.cpu.reg_read(self.regs.UC_X86_REG_EAX)),
        })
        for address in [0x10261560, 0x101450b0, 0x100628c0, 0x1025a6f0, 0x1025a780,
                        0x100444c0, 0x100ec410, 0x1024a650, 0x1035f830]:
            self.handles.append(self.cpu.hook_add(self.hook_kind, self.hook, begin=address, end=address))
        self.handles.append(self.cpu.hook_add(self.hook_kind, self.brush, begin=0x10086780, end=0x10086780))

    def ray(self):
        _, output, _, _ = self.arguments(4)
        self.cpu.mem_write(output, struct.pack('<3f', *self.case['point']))
        self.return_integer(int(self.case.get('hit', True)))

    def ground(self):
        x, z = struct.unpack('<2i', struct.pack('<2I', *self.arguments(2)))
        self.return_float(self.case.get('ground', {}).get(f'{x},{z}', self.case.get('height', 20.)))

    def payment(self):
        raw, reason = self.arguments(2)
        self.events.append(['payment', struct.unpack('<f', struct.pack('<I', raw))[0], reason])
        self.return_integer(int(self.case.get('paid', True)))

    def cell_changed(self):
        self.events.append(['cell', *struct.unpack('<2i', struct.pack('<2I', *self.arguments(2)))])
        self.return_integer()

    def dirty(self):
        self.events.append(['dirty', *struct.unpack('<3i', struct.pack('<3I', *self.arguments(3)))])
        self.return_integer()

    def refresh_area(self):
        self.events.append(['refresh', *struct.unpack('<3f', struct.pack('<3I', *self.arguments(3)))])
        self.return_integer()

    def brush(self, _cpu, _address, _size, _user):
        self.events.append(['brush', *struct.unpack('<4i', struct.pack('<4I', *self.arguments(4)))])

    def execute(self, case, configuration):
        self.case = case
        self.events = []
        self.cpu.mem_write(FLAGS, bytes(8 * 1024 * 4))
        self.cpu.mem_write(TABLE, bytes(8 * 1024 * 4))
        self.allocation = self.GRIDS + 0x200000
        self.reset_notifications(0)
        for field, x, z, byte in case['bytes']:
            self.raw_set(field, x, z, byte)
        cx, cz = [int(value) for value in case['point'][:2]]
        if case.get('influence', True):
            self.raw_set(6 if case.get('power_only', False) else 4, cx, cz, 128)
        self.set_float(0x1060f5e0, .5)
        settings = configuration | case.get('configuration', {})
        for key, address in [('BEAUTIFY_RADIUS', 0x105ad188), ('BELIEF_PER_BEAUTIFY', 0x105ad184),
                             ('BEAUTIFY_TIMEOUT', 0x10a74278), ('LE_TIMER_TICK_LENGTH', 0x105b6e84)]:
            self.set_float(address, settings[key])
        self.set_float(0x10a74274, 0.0)
        self.set_integer(0x10a74268, 1)
        self.set_integer(0x10a74270, 1)
        ok = bool(self.call(0x10086890, [0, 0, 0]) & 255)
        probes = [[kind, x, z] for kind in [1, 2, 3, 7]
                  for z in range(max(0, cz-7), cz+2) for x in range(max(0, cx-7), cx+2)]
        return dict(ok=ok, events=self.events.copy(), probes=probes, **self.observations(probes))


def main():
    root = ROOT / 'game/assets/original/campaign'
    data = extract()
    oracle = BeautifyOracle((ROOT / 'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_beautify(
        base_content(), json.loads((root / 'house-rules.json').read_text()),
        json.loads((root / 'house-terrain-frame.json').read_text()),
        json.loads((root / 'temple-effects.json').read_text()),
    )
    default = dict(point=[35.75, 35.25, 20.], bytes=[])
    cases = [
        dict(default, name='dry'),
        dict(default, name='fractional_radius', configuration={'BEAUTIFY_RADIUS': 2.4, 'BELIEF_PER_BEAUTIFY': .25}),
        dict(default, name='coast', ground={'32,32': 19., '33,32': 18., '37,37': 19., '35,35': 19.},
             configuration={'BELIEF_PER_BEAUTIFY': .25}),
        dict(default, name='overlap', bytes=[[1, 32, 32, 128], [1, 34, 34, 64], [2, 35, 34, 50], [3, 34, 35, 93]],
             configuration={'BELIEF_PER_BEAUTIFY': .25, 'BEAUTIFY_TIMEOUT': 240.}),
        dict(default, name='water', height=19., bytes=[[2, 32, 32, 12], [3, 32, 33, 91]],
             configuration={'BELIEF_PER_BEAUTIFY': .25}),
        dict(default, name='edge', point=[1.25, 1.5, 20.]),
        dict(default, name='power_influence', power_only=True),
        dict(default, name='no_influence', influence=False),
        dict(default, name='no_hit', hit=False),
        dict(default, name='cannot_pay', paid=False, configuration={'BELIEF_PER_BEAUTIFY': 1.5}),
    ]
    for case in cases:
        case['expected'] = oracle.execute(case, data['rules']['configuration'])
    result = dict(executable_sha256=data['executable_sha256'], cases=cases, native_routines=data['native_routines'],
                  adapters=[hex(address) for address in sorted(oracle.adapters)])
    path = ROOT / 'game/tests/fixtures/source_beautify.json'
    path.write_text(json.dumps(result, separators=(',', ':')) + '\n')
    print('Original Beautify terrain action:', len(cases), 'native cases')


if __name__ == '__main__':
    main()
