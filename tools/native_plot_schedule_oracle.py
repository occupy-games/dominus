"""Capture native plot dirty marking and region dispatch, independently of layout.

Original availability scans, change detection, dirty bits and ordered dispatch
execute. The already separately compared region body is replaced by an observer
that records its coordinates. No entrypoint, renderer or OS imports execute.
"""
import argparse
import hashlib
import json
import struct

from tools.house_selection import extract
from tools.native_house_selection_oracle import SelectionOracle
from tools.native_scenery_oracle import ROOT


class ScheduleOracle(SelectionOracle):
    def configure_schedule(self, data):
        self.configure_selection(data)
        self.adapters[0x1023798b] = self.dispatch
        self.handles.append(self.cpu.hook_add(self.hook_kind, self.hook, begin=0x1023798b, end=0x1023798b))

    def dirty(self):
        rows = struct.unpack('<32I', self.cpu.mem_read(0x10f6e858, 128))
        return [z*32+x for z, bits in enumerate(rows) for x in range(32) if bits & (1 << x)]

    def mark(self, x, z):
        self.cpu.mem_write(0x10f6e858, bytes(128))
        self.call(0x1025e0d0, [x, z, 0])
        return self.dirty()

    def dispatch(self):
        frame = self.cpu.reg_read(self.regs.UC_X86_REG_EBP)
        self.dispatched.append([self.integer(frame-0x44), self.integer(frame-0x5c)])
        self.cpu.reg_write(self.regs.UC_X86_REG_EIP, 0x10239cd5)

    def run(self, profile, previous, dirty):
        self.profile(profile)
        limits = self.limits()
        for i, (minimum, maximum) in enumerate(previous['sizes']):
            self.set_integer(0x1060c758+i*4, minimum)
            self.set_integer(0x110a4968+i*4, maximum)
        for key, address in [('minimum', 0x1060c764), ('maximum', 0x110a4974), ('biomes', 0x110a4978)]:
            self.set_integer(address, previous[key])
        self.cpu.mem_write(0x10f6e858, bytes(128))
        for cell in dirty:
            address = 0x10f6e858+(cell//32)*4
            self.set_integer(address, self.integer(address) | (1 << (cell % 32)))
        self.dispatched = []
        # limits() left the real availability results in the original frame.
        self.cpu.emu_start(0x10237893, 0x10239d1e, count=1000000)
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP) != 0x10239d1e:
            raise ValueError('Original plot scheduler did not finish')
        return dict(limits=limits, regions=self.dispatched, dirty=self.dirty())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default=str(ROOT/'game/tests/fixtures/source_plot_schedule.json'))
    args = parser.parse_args()
    raw = (ROOT/'data/godus2_4/godus.s86').read_bytes()
    data = extract()
    oracle = ScheduleOracle(raw)
    oracle.configure_schedule(data)
    marks = [dict(cell=[x, z], dirty=oracle.mark(x, z))
             for x in [0, 1, 31, 32, 511, 992, 1023]
             for z in [0, 1, 31, 32, 511, 992, 1023]]
    profiles = json.loads((ROOT/'game/tests/fixtures/source_house_selection.json').read_text())['profiles']
    locked, tent, lowland = [next(p for p in profiles if p['name'] == name) for name in ['locked', 'first_tent', 'lowland']]
    inputs = [
        ('unchanged_clean', tent, tent['limits'], []),
        ('unchanged_dirty', tent, tent['limits'], [1023, 0, 173, 32, 31]),
        ('first_unlock', tent, locked['limits'], []),
        ('larger_abodes', lowland, tent['limits'], [173]),
        ('locked_again', locked, tent['limits'], []),
        ('biomes_changed', tent, dict(tent['limits'], biomes=0), []),
        ('global_minimum_changed', tent, dict(tent['limits'], minimum=2), []),
        ('global_maximum_changed', tent, dict(tent['limits'], maximum=8), []),
    ]
    cases = [dict(name=name, profile=profile['name'], previous=previous, dirty=dirty,
                  expected=oracle.run(profile, previous, dirty)) for name, profile, previous, dirty in inputs]
    result = dict(executable_sha256=hashlib.sha256(raw).hexdigest(), source_sha256=data['source_sha256'],
                  table_sha256=data['table_sha256'], marks=marks, cases=cases,
                  native_routines={hex(a):oracle.image.read(a, b-a).hex() for a, b in [
                      (0x1025e0d0, 0x1025e20c), (0x102377f0, 0x1023798b), (0x10239cd5, 0x10239d1e)]},
                  adapters=[hex(a) for a in sorted(oracle.touched)],
                  scope='Original availability, change detection, dirty marking and row-major region dispatch. Region layout is an observed boundary, separately compared by native_plot_registry_oracle. Not native AOI, follower claims or a campaign playthrough.')
    (ROOT/args.output).write_text(json.dumps(result, separators=(',', ':'))+'\n')
    print('Original plot schedule:', len(marks), 'dirty neighborhoods,', len(cases), 'dispatch cases')


if __name__ == '__main__': main()
