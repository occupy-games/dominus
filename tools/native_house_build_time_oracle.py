"""Run the original modifier pass, target lookup and house frame together.

Native unlock membership, descriptor order and float32 stores execute.
Stat rows, terrain samples, model/economy callbacks and clock remain explicit.
"""
import copy
import json
import struct

from tools.building_foundation import extract as foundation_content
from tools.house_terrain_frame import extract
from tools.native_house_terrain_frame_oracle import HouseFrameOracle, state
from tools.native_scenery_oracle import ROOT
from tools.native_temple_terrain_oracle import f32
from tools.native_unlock_dispatch_oracle import SETS, UnlockOracle
from tools.reward_dispatch import key


GENERAL = ['FasterBuildTimers', 'FasterBuildTimers2']
FARM = 'FasterBuildTimers_Farms'


class BuildTimeOracle(HouseFrameOracle):
    def configure_build_time(self, descriptors):
        self.configure_house_frame()
        del self.adapters[0x100b7e80]
        self.descriptors = descriptors
        self.handles.append(self.cpu.hook_add(
            self.hook_kind, self.observe_unlock, begin=0x1015c1e0, end=0x1015c1e0,
        ))

    def observe_unlock(self, _cpu, _address, _size, _user):
        pointer, = self.arguments(1)
        name = bytes(self.cpu.mem_read(pointer, 80)).split(b'\0')[0].decode()
        self.unlock_queries.append(name)

    def refresh(self, unlocked, reset=False, values=None):
        if reset:
            self.call(0x10437ec0)
        for row in self.descriptors:
            value = (values or {}).get(row['unlock'], row['value'])
            self.set_float(int(row['value_address'], 16), value)
        UnlockOracle.load_set(self, SETS['unlocked'], ['@' + str(key(name)) for name in unlocked])
        self.unlock_queries = []
        start = 0x101b3181
        end = 0x101b31a5
        self.cpu.reg_write(self.regs.UC_X86_REG_ESP, self.STACK + 0x80000)
        self.cpu.reg_write(self.regs.UC_X86_REG_ESI, 0x105e4c00)
        self.cpu.emu_start(start, end, count=500000)
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP) != end:
            raise ValueError('Original modifier pass did not finish')
        return {
            'queries': self.unlock_queries.copy(),
            'values': {
                row['field']: self.float(int(row['destination_address'], 16))
                for row in self.descriptors
            },
        }

    def write_house(self, current):
        super().write_house(current)
        self.set_float(self.HOUSE + 0x14, current.get('build_time_override', 0.0))
        self.set_integer(self.HOUSE + 0x20, current.get('profession', 0))
        self.set_integer(self.HOUSE + 0x30, current.get('special', 0))
        if current['reference_attached']:
            self.set_integer(self.GRIDS + 0x14, current.get('attached_kind', 0))

    def work_exponent(self):
        self.foundation_event('house_stats')
        row = self.case['stats']
        pointer = self.SCRATCH + 0x8000
        self.set_float(pointer + 0x4c, row['build time'])
        self.set_float(pointer + 0x98, row['new builder contribution'])
        self.return_integer(pointer)

    def run_step(self, case):
        modifiers = self.refresh(case['unlocked'], case.get('reset', False), case.get('values'))
        self.set_float(0x10a764a0, case.get('global_override', 0.0))
        result = self.run_frame(case)
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX, self.HOUSE)
        result['target'] = self.call(0x100b7e80, floating=True)
        result['modifiers'] = modifiers
        return result


def cases():
    records = json.loads((ROOT / 'game/assets/original/campaign/house-rules.json').read_text())['records']
    types = [
        ('abode', 'Base_Rank_1', dict(special=0, profession=0)),
        ('non_special_farm', 'Farm_Rank_1', dict(special=0, profession=1)),
        ('farm', 'Farm_Rank_1', dict(special=1, profession=1)),
        ('mine', 'Mine_Rank_1', dict(special=1, profession=2)),
        ('attached_farm', 'Farm_Rank_1', dict(special=1, profession=2, reference_attached=True, attached_kind=1)),
        ('attached_mine', 'Mine_Rank_1', dict(special=1, profession=1, reference_attached=True, attached_kind=2)),
    ]
    for kind, record, fields in types:
        stats = {name: records[record]['values'][name] for name in ['build time', 'new builder contribution']}
        for gates in [[], GENERAL[:1], GENERAL[1:], GENERAL, GENERAL + [FARM]]:
            for case_type, override, local, changes, raw in [
                ('flat', 0., 0., dict(progress=8.0, workers=2), 20.),
                ('damage', -2., -1., dict(progress=3.0, uneven_count=4), 19.),
                ('restore', 0., 6., dict(state=2, damage_timer=0.5), 20.),
                ('override', 4., 6., dict(progress=5.0, workers=0), 20.),
            ]:
                yield dict(name=f'{kind}_{len(gates)}_{gates[:1]}_{case_type}', unlocked=gates, reset=True,
                           global_override=override, state=state(build_time_override=local, **fields, **changes),
                           stats=stats, ground={'default': raw})


def main():
    raw = (ROOT / 'data/godus2_4/godus.s86').read_bytes()
    content = extract()
    oracle = BuildTimeOracle(raw)
    descriptors = content['modifiers']['descriptors']
    oracle.configure_build_time(descriptors)
    examples = list(cases())
    for case in examples:
        case['expected'] = oracle.run_step(case)
    stats = {'build time': f32(5.23), 'new builder contribution': f32(0.3)}
    initial = state(progress=0.0, workers=3, special=1, profession=1)
    current = copy.deepcopy(initial)
    sequence = []
    for index in range(20):
        unlocked = GENERAL + [FARM] if index in [1, 2, 9] else []
        if index == 13:
            unlocked = [row['unlock'] for row in descriptors]
        if index == 14:
            unlocked = ['WalkFaster']
        inputs = {'build_time_override': 3.0 if index in [5, 6] else 0.0}
        current.update(inputs)
        step = dict(unlocked=unlocked, reset=index in [0, 7, 15],
                    global_override=4.0 if index in [6, 7] else 0.0,
                    stats=stats, ground={'default': 19.0 if 3 <= index <= 6 else 20.0},
                    inputs=inputs)
        if index == 9:
            step['values'] = {GENERAL[1]: f32(0.83), FARM: f32(0.73)}
        expected = oracle.run_step(dict(step, state=current))
        sequence.append(dict(step, expected=expected))
        current = copy.deepcopy(expected['state'])
    ranges = [(0x1015c1e0, 0x1015c23a), (0x101b51e0, 0x101b5213), (0x101b5260, 0x101b5281)]
    routines = dict(foundation_content()['native_routines'], **content['native_routines'])
    routines.update({hex(a): oracle.image.read(a, b - a).hex() for a, b in ranges})
    fixture = dict(executable_sha256=content['executable_sha256'], cases=examples,
                   sequence=dict(initial=initial, steps=sequence), native_routines=routines,
                   adapters=[hex(a) for a in sorted(oracle.adapters)], scope=__doc__.strip())
    path = ROOT / 'game/tests/fixtures/source_house_build_time.json'
    path.write_text(json.dumps(fixture, separators=(',', ':')) + '\n')
    print('Original house build time and modifiers:', len(examples), 'cases,', len(sequence), 'steps')


if __name__ == '__main__':
    main()
