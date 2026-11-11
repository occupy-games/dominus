"""Execute original house base-row selection and compose it with construction."""
import json
import struct

from tools.building_foundation import extract as foundation_content
from tools.house_base_stats import extract
from tools.native_house_build_time_oracle import BuildTimeOracle, FARM, GENERAL
from tools.native_house_terrain_frame_oracle import state
from tools.native_scenery_oracle import ROOT
from tools.native_temple_terrain_oracle import f32
from tools.reward_dispatch import key


ORDINARY = 0x10fc241c
ATTACHED = 0x10bc4670
ROW_BYTES = 0x130
ATTACHMENT = dict(capacity=13.25, **{
    'breeder count': 4.5, 'min belief': 5.25, 'max belief': 25.0, 'birth rate': 17.5,
})


class BaseStatsOracle(BuildTimeOracle):
    def configure_rows(self, content, houses):
        self.rules = content['rules']
        self.records = list(houses['records'].values())
        self.fields = houses['native']['fields']
        self.cpu.mem_write(ORDINARY, bytes(ROW_BYTES * 64))
        for index, (name, row) in enumerate(houses['records'].items()):
            address = ORDINARY + ROW_BYTES * index
            self.set_integer(address + 0x18, key(row['raw']['Model Name For Tex']))
            self.set_integer(address + 0x28, key(name))
            for field, value in row['values'].items():
                descriptor = self.fields[field]
                if descriptor['arithmetic'] == 'float32':
                    self.set_float(address + descriptor['offset'], value)
                else:
                    self.set_integer(address + descriptor['offset'], value)
        self.cpu.mem_write(ATTACHED, bytes(ROW_BYTES * 6))
        self.call(0x10407a70)
        for index, name in enumerate(self.rules['models']):
            assert self.integer(0x10bc55a8 + index * 4) == key(name)
        # Enter the initialization loop with the original prologue's frame.
        # Stop before the unrelated source settlement preset generation.
        frame = self.STACK + 0x80000
        for reg, value in [('ESP', frame - 0xc0), ('EBP', frame), ('EBX', 0), ('ESI', 0), ('EDI', 0)]:
            self.cpu.reg_write(getattr(self.regs, 'UC_X86_REG_' + reg), value)
        self.cpu.emu_start(0x10120ec2, 0x10120f0e, count=200000)
        assert self.cpu.reg_read(self.regs.UC_X86_REG_EIP) == 0x10120f0e
        assert bytes(self.cpu.mem_read(ATTACHED + 5 * ROW_BYTES, ROW_BYTES)) == bytes(ROW_BYTES)
        for slot, expected in enumerate(self.rules['settlement_rows'][:5]):
            assert self.integer(0x10bc4654 + 4 * slot) == expected
            assert self.cpu.mem_read(ATTACHED + slot * ROW_BYTES, ROW_BYTES) == self.cpu.mem_read(ORDINARY + expected * ROW_BYTES, ROW_BYTES)
        self.cpu.mem_write(0x10f1f75c, bytes(0x200))
        self.cpu.mem_write(0x10d9b5f8, b'\0')
        self.body = self.HOUSE + 0x74

    def write_house(self, current):
        super().write_house(current)
        self.set_integer(self.HOUSE + 0x264, current['house_index'])
        if current['reference_attached']:
            for row in self.rules['overrides']:
                self.set_float(self.GRIDS + row['offset'], current['attached_values'][row['name']])

    def row(self, index, attachment):
        current = state(house_index=index, reference_attached=attachment is not None)
        if attachment is not None:
            current.update(attached_kind=attachment['kind'], attached_values=attachment['values'])
        self.write_house(current)
        pointer = self.call(0x100b6750, [index, self.HOUSE])
        slot = -1
        if attachment is not None:
            slot = (pointer - ATTACHED) // ROW_BYTES
            index = self.rules['settlement_rows'][slot]
        elif pointer != ORDINARY + index * ROW_BYTES:
            raise ValueError('Unexpected standalone row address')
        values = {}
        if index >= 0:
            for field in self.records[index]['values']:
                descriptor = self.fields[field]
                address = pointer + descriptor['offset']
                values[field] = (self.float(address) if descriptor['arithmetic'] == 'float32'
                                 else struct.unpack('<i', self.cpu.mem_read(address, 4))[0])
        return dict(index=index, slot=slot, values=values)


def main():
    content = extract()
    root = ROOT / 'game/assets/original/campaign'
    houses = json.loads((root / 'house-rules.json').read_text())
    timing = json.loads((root / 'house-terrain-frame.json').read_text())
    oracle = BaseStatsOracle((ROOT / 'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_build_time(timing['modifiers']['descriptors'])
    del oracle.adapters[0x100b7580]
    oracle.configure_rows(content, houses)
    cases = [dict(index=index, attachment=None, expected=oracle.row(index, None))
             for index in range(len(houses['records']))]
    for kind in [*range(12), 65535, 0xffffffff]:
        for values in [ATTACHMENT, {name: f32(-0.125 * i) for i, name in enumerate(ATTACHMENT, 1)}]:
            attachment = dict(kind=kind, values=values)
            cases.append(dict(index=63, attachment=attachment, expected=oracle.row(63, attachment)))
    frames = []
    for index, kind, special, attached in [(18, 0, 0, False), (6, 1, 1, False), (12, 2, 1, False),
                                           (18, 0, 0, True), (6, 1, 1, True), (12, 2, 1, True)]:
        for phase, raw, progress in [(0, 20., 8.), (0, 19., 3.), (2, 20., 0.)]:
            for unlocked in [[], GENERAL + [FARM]]:
                house = state(house_index=index, profession=kind, special=special,
                              reference_attached=attached, state=phase, progress=progress,
                              uneven_count=4 if raw == 19 else 0, damage_timer=0.5,
                              attached_kind=kind, attached_values=ATTACHMENT,
                              build_time_override=5.5 if attached else 0.)
                case = dict(state=house, ground=dict(default=raw), unlocked=unlocked, reset=True)
                frames.append(dict(case, expected=oracle.run_step(case)))
    routines = dict(foundation_content()['native_routines'], **content['native_routines'], **timing['native_routines'])
    routines['0x100b7580'] = oracle.image.read(0x100b7580, 0x100b78e6 - 0x100b7580).hex()
    fixture = dict(executable_sha256=content['executable_sha256'], cases=cases, frames=frames,
                   native_routines=routines, adapters=[hex(a) for a in sorted(oracle.adapters)], scope=__doc__.strip())
    path = ROOT / 'game/tests/fixtures/source_house_base_stats.json'
    path.write_text(json.dumps(fixture, separators=(',', ':')) + '\n')
    print('Original house base stats:', len(cases), 'row cases,', len(frames), 'construction frames')


if __name__ == '__main__':
    main()
