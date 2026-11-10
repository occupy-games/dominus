"""Run original house selection and plot availability over resolved source rows.

Offline, optional Unicorn harness. The table and unlock set are explicit inputs;
only unlock membership/string lookup services are adapted. Original filters,
scans, biome conversion, model classification and tie decisions execute unchanged.
"""
import argparse
import hashlib
import json
from pathlib import Path

from tools.house_selection import extract
from tools.native_scenery_oracle import Oracle, ROOT


class SelectionOracle(Oracle):
    def configure_selection(self, data):
        self.entries = data['rows']
        self.keys = {key:i+1 for i,key in enumerate(sorted({r['unlock'] for r in self.entries}))}
        self.cpu.mem_write(0x10fc241c,bytes(64*0x130))
        # In-memory identities stand in for string registration. Equality is
        # preserved; the numeric hash values do not participate in selection.
        self.set_integer(0x107cdfe0,1)
        self.set_integer(0x107cdfdc,2)
        for row in self.entries:
            address = 0x10fc241c+row['index']*0x130
            for offset,key in [(4,'size'),(0x10,'kind'),(0x34,'locations'),(0x38,'biomes'),(0x3c,'order')]:
                self.set_integer(address+offset,row[key])
            self.set_integer(address+0x30,self.keys[row['unlock']])
        for key,pointer in [('biome1Index',0x1060fd2c),('biome2Index',0x1060fd30),('biome3Index',0x1060fd34)]:
            self.set_float(pointer,data['configuration'][key])
        self.adapters = {0x1015c130:self.unlocked,0x1015c1e0:self.biome_gate}
        self.handles = [self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def unlocked(self):
        key, = self.arguments(1)
        self.return_integer(int(key in self.active))

    def biome_gate(self):
        name, = self.arguments(1)
        if self.cpu.mem_read(name,18) != b'HousesBiomeLocked\0':
            raise ValueError('Unexpected source string unlock lookup')
        self.return_integer(int(self.biome_locked))

    def profile(self, profile):
        self.active = {self.keys[key] for key in profile['unlocks']}
        self.biome_locked = profile.get('biome_locked',True)

    def choose(self, size, band, scheme, kind=0, ignore_unlocks=False):
        return self.call(0x100b72c0,[size,band,scheme,int(ignore_unlocks),int(kind!=0),kind])

    def limits(self):
        # Enter/leave the original routine around its availability phase; later
        # existing/new plot mutation is outside this capture.
        self.cpu.reg_write(self.regs.UC_X86_REG_ESP,self.STACK+0x80000)
        self.cpu.mem_write(self.STACK+0x80000,b'\0'*4)
        self.cpu.mem_write(self.SCRATCH+0x700,b'\xdb\xe3')
        self.cpu.emu_start(self.SCRATCH+0x700,self.SCRATCH+0x702)
        self.cpu.emu_start(0x102377f0,0x10237893,count=1000000)
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=0x10237893:
            raise ValueError('Original plot availability did not finish')
        frame = self.cpu.reg_read(self.regs.UC_X86_REG_EBP)
        return {'sizes':[[self.integer(frame-0x10+i*4),self.integer(frame-0x1c+i*4)] for i in range(3)],
                'minimum':self.integer(frame-0x44),'maximum':self.cpu.reg_read(self.regs.UC_X86_REG_EBX),
                'biomes':self.integer(frame-0x38)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'game/tests/fixtures/source_house_selection.json')
    args = parser.parse_args()
    data = extract()
    raw = (ROOT/'data/godus2_4/godus.s86').read_bytes()
    oracle = SelectionOracle(raw)
    oracle.configure_selection(data)
    all_keys = sorted({r['unlock'] for r in data['rows']} - {'NeverUnlocked'})
    profiles = [
        {'name':'locked','unlocks':[]},
        {'name':'first_tent','unlocks':['PlotsAppear']},
        {'name':'lowland','unlocks':['PlotsAppear','Low_Rank_1','Low_Rank_2']},
        {'name':'homeworld','unlocks':['PlotsAppear']+[key for key in all_keys if key.startswith(('Low_','Mid_','High_'))]},
        {'name':'imperial','unlocks':['PlotsAppear']+[key for key in all_keys if key.startswith('Imp_')]},
        {'name':'all_advances','unlocks':all_keys},
        {'name':'biomes_unlocked','unlocks':all_keys,'biome_locked':False},
        {'name':'ignore_unlocks','unlocks':[],'ignore_unlocks':True},
    ]
    result = {'executable_sha256':hashlib.sha256(raw).hexdigest(),'source_sha256':data['source_sha256'],
              'table_sha256':data['table_sha256'],'profiles':[],
              'configuration':data['configuration'],
              'columns':['size','band','scheme','kind','index'],
              'scope':'Original selector and plot availability only; explicit resolved rows/unlock membership. Not plot claims, follower decisions, production, or a full native CSV loader.',
              'native_routines':dict(data['native_routines'])}
    result['native_routines']['0x102377f0'] = oracle.image.read(0x102377f0,0x10237893-0x102377f0).hex()
    for profile in profiles:
        oracle.profile(profile)
        samples = [[size,band,scheme,kind,oracle.choose(size,band,scheme,kind,profile.get('ignore_unlocks',False))]
                   for size in range(1,17) for band in range(3) for scheme in [-1,17,19,18] for kind in range(3)]
        result['profiles'].append(dict(profile,samples=samples,limits=oracle.limits()))
    result['adapters'] = [hex(a) for a in sorted(oracle.touched)]
    args.output.write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Original building selection:',sum(len(p['samples']) for p in result['profiles']),'cases;',
          [(p['name'],p['limits']) for p in result['profiles'][:3]])


if __name__ == '__main__': main()
