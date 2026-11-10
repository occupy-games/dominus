"""Original authored-area unlock/radius controller with the actual raster kernel.

Runs 0x1025ab20 with no houses/dynamic entities. Unlock membership, fixed delta,
paused/debug services, heap storage and presentation notifications are adapters.
Area decisions, timing, circle registration, raster writes and plot dirty marking
execute original instructions. No entrypoint or OS/device services execute.
"""
import argparse
import hashlib
import json
import struct

from tools.current_cards import decode_archive, rows
from tools.native_influence_oracle import InfluenceOracle
from tools.native_scenery_oracle import ROOT


class AreaOracle(InfluenceOracle):
    def configure_areas(self, case):
        self.configure_influence()
        self.areas = case['areas']
        self.keys = {key:index+1 for index,key in enumerate(sorted({a[k] for a in self.areas for k in ['unlock','sculpt_unlock']}))}
        self.cpu.mem_write(0x10fcc2f8,bytes(64*52))
        for index, area in enumerate(self.areas):
            pointer = 0x10fcc2f8+index*52
            for offset,field in [(4,'unlock'),(8,'sculpt_unlock')]:self.set_integer(pointer+offset,self.keys[area[field]])
            for offset,field in [(12,'x'),(16,'z'),(20,'radius')]:self.set_float(pointer+offset,area[field])
            self.set_integer(pointer+24,int(area['force']))
            self.set_integer(pointer+28,int(area['powers_only']))
            self.set_float(pointer+32,case.get('initial_radius',0.))
        self.set_integer(0x10d9b670,0)
        self.set_integer(0x10d9b66c,1)
        self.set_integer(0x10fcd47e,0xffff) # No active houses.
        self.set_integer(0x10fcc2f6,0xffff) # No active dynamic influence circles.
        self.set_integer(0x10fcc2e8,0)
        self.set_integer(0x10fccffc,0)
        self.set_integer(0x110d6130,0)
        self.set_float(0x110d5d98,0.)
        self.adapters.update({
            0x10179970:lambda:self.return_float(self.delta),
            0x10179950:lambda:self.return_float(self.delta),
            0x101bfa10:lambda:self.return_integer(),
            0x1019b470:lambda:self.return_integer(),
            0x1015c130:self.unlocked,
            0x1022aed0:self.activated,
            0x1025a780:lambda:self.return_integer(), # Presentation/spatial-cache notification.
            0x1025a6f0:lambda:self.return_integer(), # Presentation cache after a cleared tile.
            0x103452c0:lambda:self.return_integer(), # Heap release, storage only.
            0x1035f830:lambda:self.return_integer(), # Stack-cookie diagnostic.
            0x10245d30:self.event,
        })
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles = [self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def unlocked(self):
        key, = self.arguments(1)
        self.return_integer(int(key in self.active))

    def activated(self):
        index, = self.arguments(1)
        self.return_integer(int(index in self.activated_areas))

    def event(self):
        pointer, argument = self.arguments(2)
        name = bytes(self.cpu.mem_read(pointer,100)).split(b'\0')[0].decode()
        self.events.append(dict(name=name,argument=argument))
        self.return_integer()

    def advance(self, step):
        self.delta = step.get('delta',.1)
        self.active = {self.keys[key] for key in step.get('unlocks',[])}
        self.activated_areas = step.get('activated',[])
        self.set_float(0x1057b450,1. if step.get('expand',True) else 0.)
        self.cpu.mem_write(0x110348d0,bytes([int(step.get('force',False))]))
        self.set_integer(0x10fcc2e8,int(step.get('rebuild',False)))
        self.cpu.mem_write(0x10f6e858,bytes(128)) # Prior tick's plot scan consumed these bits.
        self.events = []
        self.call(0x1025ab20,limit=100000000)
        mask = struct.unpack('<32I',self.cpu.mem_read(0x10f6e858,128))
        return dict(radii=[self.float(0x10fcc2f8+i*52+32) for i in range(len(self.areas))],
                    powers_only=[bool(self.integer(0x10fcc2f8+i*52+28)) for i in range(len(self.areas))],
                    changed=bool(self.integer(0x110d6130)),
                    dirty=[z*32+x for z,value in enumerate(mask) for x in range(32) if value&(1<<x)],
                    events=self.events,fields=self.capture(self.bounds))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_influence_areas.json'))
    args = parser.parse_args()
    raw = (ROOT/'data/godus2_4/godus.s86').read_bytes()
    archive = (ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    files = decode_archive(archive)
    area = dict(unlock='area',sculpt_unlock='sculpt',x=160.,z=120.,radius=4.,force=True,powers_only=False)
    defaults = [dict(delta=.1) for _ in range(5)]+[dict(delta=1.),dict(delta=1.),dict(delta=.1)]
    cases = [dict(name='desktop_expand',areas=[area],steps=defaults),
             dict(name='instant',areas=[area],steps=[dict(expand=False),dict(expand=False)]),
             dict(name='unlock',areas=[dict(area,force=False)],steps=[{},dict(unlocks=['area']),dict(unlocks=['area'],delta=2.),dict(unlocks=['area'])]),
             dict(name='activated',areas=[dict(area,force=False)],steps=[{},dict(activated=[0]),dict(activated=[0],delta=2.)]),
             dict(name='power_conversion',areas=[dict(area,powers_only=True)],steps=[dict(expand=False),dict(expand=False,unlocks=['sculpt']),dict(expand=False,unlocks=['sculpt'])]),
             dict(name='forced_conversion',areas=[dict(area,powers_only=True)],steps=[dict(expand=False),dict(expand=False,unlocks=['sculpt'],force=True)]),
             dict(name='relock',areas=[dict(area,force=False)],steps=[dict(expand=False,unlocks=['area']),dict(expand=False)]),
             dict(name='rebuild',areas=[area],steps=[dict(expand=False),dict(expand=False,rebuild=True,force=True),dict(expand=False)]),
             dict(name='overlap',areas=[dict(area,x=158.),dict(area,x=164.,radius=7.)],steps=defaults),
             dict(name='fractional',areas=[dict(area,x=160.125,z=120.375,radius=7.25)],steps=defaults),
             dict(name='offmap_center',areas=[dict(area,x=-1.25,z=.5)],bounds=[0,0,16,16],steps=defaults)]
    source_areas = [dict(unlock=row[0],sculpt_unlock=row[1],x=float(row[2]),z=float(row[3]),radius=float(row[4]),force=bool(int(row[5])),powers_only=bool(int(row[6])))
                    for row in rows(files,'initialworldsetup6/influence_areas.csv')[1:] if len(row)>6 and row[2]]
    cases.append(dict(name='homeworld_initial',areas=source_areas,bounds=[130,65,190,155],steps=[dict(delta=.1),dict(delta=1.),dict(delta=1.),dict(delta=.1)]))
    oracle = None
    for case in cases:
        oracle = AreaOracle(raw)
        oracle.bounds = case.setdefault('bounds',[146,106,178,138])
        oracle.configure_areas(case)
        case['states'] = [oracle.advance(step) for step in case['steps']]
        print('Original influence areas:',case['name'],[s['radii'][:3] for s in case['states']],flush=True)
    result = dict(executable_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=hashlib.sha256(archive).hexdigest(),
                  area_table_sha256=hashlib.sha256(files['initialworldsetup6/influence_areas.csv']).hexdigest(),
                  hardware_table_sha256=hashlib.sha256(files['hwlevelcontrols.csv']).hexdigest(),cases=cases,
                  native_routines={hex(a):oracle.image.read(a,b-a).hex() for a,b in [
                      (0x1025ab20,0x1025b23b),(0x10257780,0x1025785f),(0x10025f10,0x10025f34),(0x100cf9d0,0x100cfa67)]},
                  adapters=[hex(a) for a in sorted(oracle.adapters)],
                  scope='Original authored-area controller with no active houses or dynamic circles. Explicit unlock/activation sets and fixed delta; original raster, expansion, conversion and plot dirty marking execute. Not native whole-game initialization or follower claims.')
    (ROOT/args.output).write_text(json.dumps(result,separators=(',',':'))+'\n')


if __name__ == '__main__':main()
