"""Capture original environment arithmetic and the composed house stat getter."""
import copy
import json
import struct

from tools.house_base_stats import extract as base_content
from tools.house_environment import extract, f32
from tools.native_house_base_stats_oracle import ATTACHED, ORDINARY, ROW_BYTES, ATTACHMENT, BaseStatsOracle
from tools.native_house_terrain_frame_oracle import state
from tools.native_scenery_oracle import ROOT
from tools.native_unlock_dispatch_oracle import SETS, UnlockOracle
from tools.reward_dispatch import key


BUFFS = 0x10f1f75c
OPERATIONS = 0x10f20b74
FIELDS = {'capacity': 0x40, 'belief modifier': 0x64, 'build time': 0x4c, 'new builder contribution': 0x98}


class EnvironmentOracle(BaseStatsOracle):
    def configure_environment(self, base, houses, timing, shrine):
        self.configure_build_time(timing['modifiers']['descriptors'])
        del self.adapters[0x100b7580]
        self.configure_rows(base, houses)
        self.shrine = [record for record in shrine['records'] if record['family'] == 1]
        self.handles.append(self.cpu.hook_add(
            self.hook_kind, self.observe_gate, begin=0x1015c130, end=0x1015c130,
        ))

    def observe_gate(self, _cpu, _address, _size, _user):
        identity, = self.arguments(1)
        self.gates.append(identity)

    def load_environment(self, records, unlocked):
        self.cpu.mem_write(BUFFS, bytes(16 * 32))
        self.cpu.mem_write(OPERATIONS, bytes(16 * 36))
        for index, record in enumerate(records):
            address = BUFFS + index * 32
            for offset, name in enumerate(['abode', 'monastery', 'farm', 'mine']):
                self.set_integer(address + offset * 4, record[name])
            self.set_float(address + 16, record['cap'])
            self.set_integer(address + 20, key(record['unlock']))
            self.set_integer(address + 24, record['kind'])
            self.set_integer(address + 28, 1)
            effect = OPERATIONS + index * 36
            self.set_integer(effect, record['index'])
            self.set_float(effect + 4, record['value'])
            self.set_integer(effect + 8, record['operation'])
        UnlockOracle.load_set(self, SETS['unlocked'], ['@' + str(key(name)) for name in unlocked])

    def configure_case(self, case):
        self.load_environment(case['records'], case['unlocked'])
        self.cpu.mem_write(0x10f2025c, bytes(64 * 36))
        for index, record in enumerate(self.shrine):
            address = 0x10f2025c + index * 36
            for offset, flag in enumerate(['abode', 'monastery', 'farm', 'mine']):
                self.set_integer(address + offset * 4, record[flag])
            self.set_integer(address + 0x18, record['index'])
            self.set_float(address + 0x1c, record['value'])
            self.set_integer(address + 0x20, record['operation'])
        house = case['house']
        if house['reference_attached']:
            slot = self.rules['kind_slots'][house['attached_kind']]
            address = ATTACHED + slot * ROW_BYTES
        else:
            address = ORDINARY + house['house_index'] * ROW_BYTES
        for field, value in case['row_values'].items():
            self.set_float(address + FIELDS[field], value)

    def write_house(self, current):
        super().write_house(current)
        for index, count in enumerate(current['nearby']):
            self.set_integer(self.HOUSE + 0x244 + 4 * index, count)
        self.set_float(self.HOUSE + 0x250, current['beauty_fraction'])
        for index, word in enumerate(current['mask']):
            self.set_integer(self.HOUSE + 0xc + 4 * index, word)

    def run_stats(self, case):
        self.configure_case(case)
        self.body = self.HOUSE + 0x74
        self.write_house(case['house'])
        self.gates = []
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX, self.HOUSE)
        address = self.call(0x100b7580)
        return dict(values={name: self.float(address + offset) for name, offset in FIELDS.items()},
                    gates=self.gates.copy())


def cases(source):
    profiles = [(18, 0, 0, False), (50, 0, 0, False), (6, 1, 1, False),
                (12, 2, 1, False), (18, 0, 0, True), (18, 2, 1, True)]
    for index, kind, special, attached in profiles:
        for nearby, beauty in [([0, 0, 0], 0.), ([7, 3, 12], .5), ([1000, 1000, 1000], 1.)]:
            for gates in [[], ['AlwaysUnlocked'], ['AlwaysUnlocked', 'TreeBuff_1', 'TreeBuff_2']]:
                house = state(house_index=index, profession=kind, special=special,
                              reference_attached=attached, attached_kind=kind, attached_values=ATTACHMENT,
                              nearby=nearby, beauty_fraction=beauty, mask=[3, 0])
                yield dict(house=house, unlocked=gates, records=source, row_values={'belief modifier': 1.25})
    for kind in range(4):
        for operation in [0, 1]:
            for cap in [0.5, 1.0, 2.0]:
                for value in [0.75, 1.25]:
                    # Apply to the same field as the shrine, to check pass order.
                    record = dict(source[0], kind=kind, operation=operation, cap=cap, value=value,
                                  field='capacity', index=16, unlock='AlwaysUnlocked')
                    house = state(house_index=18, profession=0, special=0, nearby=[3, 6, 9],
                                  beauty_fraction=.625, mask=[1, 0])
                    yield dict(house=house, unlocked=['AlwaysUnlocked'], records=[record],
                               row_values={'belief modifier': 1.25})


def main():
    root = ROOT / 'game/assets/original/campaign'
    content = extract()
    base = base_content()
    houses = json.loads((root / 'house-rules.json').read_text())
    timing = json.loads((root / 'house-terrain-frame.json').read_text())
    shrine = json.loads((root / 'temple-effects.json').read_text())
    oracle = EnvironmentOracle((ROOT / 'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_environment(base, houses, timing, shrine)
    contributions = []
    for kind in range(4):
        for operation in [0, 1]:
            for cap in [0.5, 1., 2.]:
                for value in [f32(.99), f32(1.05)]:
                    for sample in ([0., .25, .75, 1.] if kind == 2 else [0., 1., 15., 1000.]):
                        record = dict(content['records'][0], kind=kind, operation=operation, cap=cap, value=value)
                        oracle.load_environment([record], [])
                        bits, = struct.unpack('<I', struct.pack('<f', sample))
                        result = oracle.call(0x100b50f0, [0, bits], floating=True)
                        contributions.append(dict(record=record, sample=sample, expected=result))
    stats = list(cases(content['records']))
    for case in stats:
        case['expected'] = oracle.run_stats(case)
    routines = dict(base['native_routines'], **content['native_routines'])
    for start, end in [(0x100b7580, 0x100b7744), (0x100b6e90, 0x100b7012), (0x1015c130, 0x1015c16c)]:
        routines[hex(start)] = oracle.image.read(start, end - start).hex()
    fixture = dict(executable_sha256=content['executable_sha256'], source_sha256=content['source_sha256'],
                   contributions=contributions, stats=stats, native_routines=routines,
                   adapters=[hex(a) for a in sorted(oracle.adapters)], scope=__doc__.strip())
    path = ROOT / 'game/tests/fixtures/source_house_environment.json'
    path.write_text(json.dumps(fixture, separators=(',', ':')) + '\n')
    print('Original environment buffs:', len(contributions), 'contributions,', len(stats), 'stat queries')


if __name__ == '__main__':
    main()
