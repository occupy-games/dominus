"""Execute the original house-only full and area surroundings refresh paths."""
import copy
import json
import struct

from tools.house_base_stats import extract as base_content
from tools.house_environment import extract
from tools.native_house_environment_oracle import EnvironmentOracle, ORDINARY, ROW_BYTES
from tools.native_house_terrain_frame_oracle import state
from tools.native_scenery_oracle import ROOT


POSITIONS = {3: [-1.75, 1.25, 6.0], 1: [3.25, 1.25, 6.0], 4: [16.0, 4.0, 6.0]}
VISION_INDEX = 0xd4 // 4
FIELD_VALUES = [0.0, 0.4999999701976776, 0.5, 0.5000000596046448, 0.75, 1.0, 0.25]


def pool():
    houses = {}
    for id, index in [(3, 18), (1, 6), (4, 12)]:
        houses[str(id)] = state(handle=id, house_index=index, position=POSITIONS[id],
                                profession=0, special=0, nearby=[5, 6, 7], beauty_fraction=.5, mask=[0, 0])
    return dict(capacity=5, active=[3, 1, 4], free=[0, 2], slots=houses)


class SurroundingsOracle(EnvironmentOracle):
    def configure_surroundings(self, base, houses, timing, shrine):
        self.configure_environment(base, houses, timing, shrine)
        self.pool_base = self.HOUSE
        self.scenery_pool = 0x31900000
        self.adapters.update({0x1012ec90: self.scenery_query, 0x100cf550: self.beauty, 0x100cf4b0: self.blight})
        for address in [0x1012ec90, 0x100cf550, 0x100cf4b0]:
            self.handles.append(self.cpu.hook_add(self.hook_kind, self.hook, begin=address, end=address))
        for address, callback in [(0x100b7460, self.begin_counts), (0x100b751d, self.release)]:
            self.handles.append(self.cpu.hook_add(self.hook_kind, callback, begin=address, end=address))

    def begin_counts(self, _cpu, _address, _size, _user):
        house = self.cpu.reg_read(self.regs.UC_X86_REG_ECX)
        self.house_id = (house - self.pool_base) // 0x2d8

    def scenery_query(self):
        tag, x, z, radius, *flags = self.arguments(10)
        args = [tag, *struct.unpack('<3f', struct.pack('<3I', x, z, radius)), *flags]
        house = self.pool_base + self.house_id * 0x2d8
        counts = [self.integer(house + 0x244 + 4 * i) for i in range(3)]
        self.log_events.append(['query', self.house_id, args, counts])
        objects = self.case['objects'].get(str(self.house_id), [])
        for i, object_ in enumerate(objects):
            pointer = self.scenery_pool + i * 0x200
            self.set_integer(pointer + 0x34, object_['type'])
            self.set_integer(pointer + 0xac, object_['mode'])
            self.set_integer(self.SCRATCH + 0x2000 + i * 4, pointer)
            node = 0x10c58e68 + object_['node'] * 12
            next_ = 0x10c58e68 + objects[i + 1]['node'] * 12 if i + 1 < len(objects) else 0
            self.set_integer(node, self.SCRATCH + 0x2000 + i * 4)
            self.set_integer(node + 4, next_)
            self.set_integer(node + 8, self.SCRATCH + 0x1f00)
        self.return_integer(0x10c58e68 + objects[0]['node'] * 12 if objects else 0)

    def release(self, _cpu, _address, _size, _user):
        node = self.cpu.reg_read(self.regs.UC_X86_REG_EAX)
        self.log_events.append(['release', self.house_id, node])

    def beauty(self):
        flag, x, z = self.arguments(3)
        assert flag == 1
        x, z = struct.unpack('<2i', struct.pack('<2I', x, z))
        self.log_events.append(['beauty', x, z])
        self.return_float(FIELD_VALUES[(x * 3 + z * 5 + self.case['phase']) % len(FIELD_VALUES)])

    def blight(self):
        x, z = struct.unpack('<2i', struct.pack('<2I', *self.arguments(2)))
        self.log_events.append(['blight', x, z])
        self.return_float(0.)

    def run_refresh(self, case, current):
        self.case = case
        self.log_events = []
        self.gates = []
        self.cpu.mem_write(0x10f1f75c, bytes(16 * 32))
        self.load_environment(case['records'], ['AlwaysUnlocked'])
        self.cpu.mem_write(0x10f2025c, bytes(64 * 36))
        for index, value in case['radii'].items():
            self.set_float(ORDINARY + int(index) * ROW_BYTES + VISION_INDEX * 4, value)
        self.set_integer(0x10fcd474, self.pool_base)
        self.cpu.mem_write(0x10fcd47e, struct.pack('<H', current['active'][0] if current['active'] else 0xffff))
        self.cpu.mem_write(0x10f8f8e2, b'\xff\xff')
        for i, id in enumerate(current['active']):
            self.HOUSE = self.pool_base + id * 0x2d8
            self.body = self.HOUSE + 0x74
            self.write_house(current['slots'][str(id)])
            link = current['active'][i + 1] if i + 1 < len(current['active']) else 0xffff
            self.cpu.mem_write(self.HOUSE, struct.pack('<H', link))
        area = case.get('area', [])
        args = struct.unpack('<3I', struct.pack('<3f', *area)) if area else []
        self.call(0x100444c0 if area else 0x10044670, args)
        result = copy.deepcopy(current)
        for id in current['active']:
            address = self.pool_base + id * 0x2d8
            house = result['slots'][str(id)]
            house['nearby'] = [self.integer(address + 0x244 + 4 * i) for i in range(3)]
            house['beauty_fraction'] = self.float(address + 0x250)
        self.HOUSE = self.pool_base
        return dict(pool=result, events=self.log_events.copy())


def main():
    content = extract()
    base = base_content()
    root = ROOT / 'game/assets/original/campaign'
    houses = json.loads((root / 'house-rules.json').read_text())
    timing = json.loads((root / 'house-terrain-frame.json').read_text())
    shrine = json.loads((root / 'temple-effects.json').read_text())
    oracle = SurroundingsOracle((ROOT / 'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_surroundings(base, houses, timing, shrine)
    objects = [
        dict(node=node, type=type_, mode=mode)
        for node, type_, mode in [(9, 20, 0), (2, 14, 2), (7, 15, 2), (3, 19, 1), (1, 19, 2), (8, -1, 2)]
    ]
    vision_buff = dict(content['records'][1], index=VISION_INDEX, field='visionradius', value=2.0)
    cases = []
    for phase, area in enumerate([[], [2.25, 1.25, 0.], [2.249999761581421, 1.25, 0.],
                                  [3.25, 1.25, 0.], [-2.25, 1.25, 0.5], [50., 50., 1.], []]):
        current = pool()
        if phase == 6:
            current = dict(capacity=5, active=[], free=list(range(5)), slots={})
        case = dict(area=area, objects={'3': objects, '4': objects[:1]}, phase=phase,
                    radii={'18': 2., '6': 2.75, '12': 1.},
                    records=[] if phase in [1, 2] else [vision_buff])
        cases.append(dict(case, initial=current, expected=oracle.run_refresh(case, current)))
    initial = pool()
    current = copy.deepcopy(initial)
    sequence = []
    for phase in range(12):
        area = [] if phase % 3 == 0 else [-1.75 + phase, 1.25, 1.0]
        step = dict(phase=phase, area=area, radii={'18': 2., '6': 2.75, '12': 1.},
                    records=[vision_buff], objects={'3': objects[phase % 6:], '1': objects[:phase % 6]})
        expected = oracle.run_refresh(step, current)
        current = copy.deepcopy(expected['pool'])
        sequence.append(dict(step, expected=expected))
    fixture = dict(executable_sha256=content['executable_sha256'], cases=cases, fields=FIELD_VALUES,
                   sequence=dict(initial=initial, steps=sequence),
                   native_routines=content['surroundings_routines'],
                   adapters=[hex(address) for address in sorted(oracle.adapters)])
    path = ROOT / 'game/tests/fixtures/source_house_surroundings.json'
    path.write_text(json.dumps(fixture, separators=(',', ':')) + '\n')
    print('Original house surroundings:', len(cases), 'refresh cases,', len(sequence), 'steps')


if __name__ == '__main__':
    main()
