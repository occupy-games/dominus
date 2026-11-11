"""Run the original land effect countdown with a supplied millisecond clock."""
import json
import struct

from tools.beautify import extract
from tools.house_base_stats import extract as base_content
from tools.native_map_fields_oracle import FLAGS, TABLE, MapFieldsOracle
from tools.native_scenery_oracle import ROOT


class LandEffectTimerOracle(MapFieldsOracle):
    ANCHOR = 0x10a8a588
    INITIALIZED = 0x10a8a590

    def configure_timer(self, base, houses, timing, shrine):
        self.configure_surroundings(base, houses, timing, shrine)
        self.configure_fields()
        adapters = {0x1035d390: self.clock, 0x1025a6f0: self.cell_changed,
                    0x1035f830: lambda: self.return_integer(self.cpu.reg_read(self.regs.UC_X86_REG_EAX))}
        self.adapters.update(adapters)
        for address in adapters:
            self.handles.append(self.cpu.hook_add(self.hook_kind, self.hook, begin=address, end=address))

    def clock(self):
        self.cpu.reg_write(self.regs.UC_X86_REG_EDX, self.now >> 32)
        self.return_integer(self.now)

    def cell_changed(self):
        self.changed.append(list(self.arguments(2)))
        self.return_integer()

    def execute(self, case):
        self.cpu.mem_write(FLAGS, bytes(8 * 1024 * 4))
        self.cpu.mem_write(TABLE, bytes(8 * 1024 * 4))
        self.allocation = self.GRIDS + 0x200000
        self.reset_notifications(case['serial'])
        self.cpu.mem_write(self.ANCHOR, struct.pack('<Q', case.get('anchor', 0)))
        self.set_integer(self.INITIALIZED, int('anchor' in case))
        self.set_float(0x105b6e84, case['period'])
        for kind, x, z, byte in case['bytes']:
            self.raw_set(kind, x, z, byte)
        for step in case['steps']:
            self.now = step['now']
            self.changed = []
            argument, = struct.unpack('<I', struct.pack('<f', step.get('override', -1.0)))
            self.call(0x100d0730, [argument])
            anchor, = struct.unpack('<Q', self.cpu.mem_read(self.ANCHOR, 8))
            step['expected'] = dict(anchor=anchor, changed=self.changed, **self.observations(case['probes']))


def main():
    root = ROOT / 'game/assets/original/campaign'
    data = extract()
    oracle = LandEffectTimerOracle((ROOT / 'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_timer(
        base_content(), json.loads((root / 'house-rules.json').read_text()),
        json.loads((root / 'house-terrain-frame.json').read_text()),
        json.loads((root / 'temple-effects.json').read_text()),
    )
    base = dict(
        serial=0xfffffffe,
        bytes=[[7, 3, 0, 1], [7, 0, 1, 1], [7, 32, 0, 1], [7, 100, 100, 1],
               [7, 6, 2, 2], [7, 7, 2, 3], [7, 8, 2, 12], [7, 9, 2, 40],
               [1, 3, 0, 128], [1, 1, 1, 63], [2, 0, 1, 50], [3, 3, 0, 91],
               [2, 32, 0, 128], [1, 6, 2, 128], [1, 7, 2, 128], [1, 8, 2, 128],
               [1, 9, 2, 128], [5, 3, 0, 91]],
        probes=[[kind, x, z] for kind in [1, 2, 3, 7] for x, z in
                [(3, 0), (0, 1), (32, 0), (100, 100), (6, 2), (7, 2), (8, 2), (9, 2), (1, 1)]]
               + [[5, 3, 0]],
    )
    period = data['rules']['configuration']['LE_TIMER_TICK_LENGTH']
    high = 1 << 32
    cases = [
        dict(base, name='fixed_clock', period=period, steps=[dict(now=now) for now in
             [1000, 30999, 31000, 60999, 61037, 121038, 121999, 421000, 752000, 782000]]),
        dict(base, name='explicit_elapsed', period=period, anchor=1000, steps=[
            dict(now=1200, override=.0005), dict(now=1500, override=29.999), dict(now=750, override=30),
            dict(now=5000, override=360), dict(now=34999), dict(now=35000), dict(now=150000, override=0),
            dict(now=520000, override=0),
        ]),
        dict(base, name='high_word_fractional_period', period=.0309, anchor=high-15, steps=[
            dict(now=high+14), dict(now=high+15), dict(now=high+7), dict(now=high+75),
            dict(now=high+160, override=.03099), dict(now=high+190),
        ]),
    ]
    for case in cases:
        oracle.execute(case)
    result = dict(executable_sha256=data['executable_sha256'], native_routines=data['timer_routines'],
                  adapters=[hex(address) for address in sorted(oracle.adapters)], cases=cases)
    path = ROOT / 'game/tests/fixtures/source_land_effect_timer.json'
    path.write_text(json.dumps(result, separators=(',', ':')) + '\n')
    print('Original land effect timer:', sum(len(case['steps']) for case in cases), 'native clock transitions')


if __name__ == '__main__':
    main()
