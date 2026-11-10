"""Execute original pack/sticker/card binding and limit-registration passes.

Only balanced-tree insertion/allocation is adapted. Original tree walks, detail
binding, zero-row reset helpers, hashes and actual fixed-map limit insertion run.
The bounded internal block excludes unrelated job-table initialization and the
outer application startup. No original entrypoint, asset loading or OS executes.
"""
import copy
import json
import random

from tools.reward_catalog import extract
from tools.native_availability_oracle import NativeAvailabilityStorage,empty
from tools.native_card_research_oracle import card,sticker
from tools.native_reward_dispatch_oracle import DispatchOracle,pack
from tools.native_scenery_oracle import ROOT


LAYOUT={
    'packs':dict(data=0x10f0302c,stride=60,map=0x10f06c2c,details=0x10f06c38,info_stride=16,info_map=0x10f07c38,fallback=0x10d991d8),
    'stickers':dict(data=0x10f07ef0,stride=36,map=0x10f0a2f0,details=0x10f0a2fc,info_stride=16,info_map=0x10f0b2fc,fallback=0x10d992a4),
    'cards':dict(data=0x10f0b30c,stride=56,map=0x10f0eb0c,details=0x10f0eb18,info_stride=80,info_map=0x10f13b18,fallback=0x10d990c8)}


class CatalogOracle(DispatchOracle):
    def configure_catalog(self):
        self.adapters={0x101a7280:self.insert_catalog}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def insert_catalog(self):
        target=self.cpu.reg_read(self.regs.UC_X86_REG_ECX)
        output,hint,value=self.arguments(3)
        identity=self.integer(value)
        header=self.integer(target)
        # Original code writes registry values after insertion. Retain those
        # writes when the storage adapter rebalances the controlled tree.
        entries={key:self.integer(pointer+20) for key,pointer in self.nodes[header].items()}
        entries.setdefault(identity,0)
        self.tree(header,entries)
        self.set_integer(target+4,len(entries))
        self.set_integer(output,self.nodes[header][identity])
        self.return_integer(output,pop=12)

    def load_catalog(self,case):
        self.case=case
        self.heap=self.POOL+0x10000
        self.trees={};self.nodes={}
        self.storage=NativeAvailabilityStorage(self,case['availability'])
        for group,layout in LAYOUT.items():
            self.cpu.mem_write(layout['data'],bytes(256*layout['stride']))
            self.cpu.mem_write(layout['details'],bytes(256*layout['info_stride']))
            for i,identity in enumerate(case['details'][group]):self.set_integer(layout['details']+i*layout['info_stride'],identity)
            self.install(layout['map'],{})
            self.install(layout['info_map'],{})
            for i,row in enumerate(case['records'][group]):
                pointer=layout['data']+i*layout['stride']
                self.set_integer(pointer,row['id'])
                text=self.alloc(len(row.get('name','').encode())+1)
                self.cpu.mem_write(text,row.get('name','').encode()+b'\0')
                self.set_integer(pointer+4,text)
                if group=='packs':
                    self.set_integer(pointer+0xc,row.get('type',0))
                    for slot,value in enumerate(row['slots']):
                        self.set_integer(pointer+0x14+8*slot,value['count'])
                        self.set_integer(pointer+0x18+8*slot,value['reward'])
                if group=='stickers':
                    self.cpu.mem_write(pointer+0xc,bytes([int(row['internal'])]))
                    self.set_integer(pointer+0x10,row.get('era',0))
                    for slot in range(2):
                        self.set_integer(pointer+0x14+4*slot,row['categories'][slot])
                        self.set_integer(pointer+0x1c+4*slot,row['counts'][slot])
                if group=='cards':
                    for offset,name in [(0xc,'type'),(0x14,'reward_type'),(0x18,'category'),(0x1c,'research_needed'),(0x20,'slot_20'),(0x28,'max_collectable'),(0x2c,'silent'),(0x34,'happiness')]:
                        self.set_integer(pointer+offset,row.get(name,0))
        self.set_integer(0x10f0b308,len(case['records']['cards']))

    def bind(self):
        frame=self.STACK+0x80000
        self.cpu.reg_write(self.regs.UC_X86_REG_EBP,frame)
        self.cpu.reg_write(self.regs.UC_X86_REG_ESP,frame-0x100)
        self.cpu.reg_write(self.regs.UC_X86_REG_EBX,0)
        self.error=''
        self.cpu.emu_start(0x101ab265,0x101ab7cb,count=6000000)
        if self.error:raise ValueError(self.error)
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=0x101ab7cb:raise ValueError('Catalog instruction budget exhausted')
        records=copy.deepcopy(self.case['records'])
        registry={};details={}
        for group,layout in LAYOUT.items():
            registry[group]={}
            details[group]={}
            for owner,result,base,stride in [(layout['map'],registry[group],layout['data'],layout['stride']),
                                              (layout['info_map'],details[group],layout['details'],layout['info_stride'])]:
                for identity,node in self.nodes[self.integer(owner)].items():
                    result['@'+str(identity)]=(self.integer(node+20)-base)//stride
            for i,row in enumerate(records[group]):
                pointer=layout['data']+i*layout['stride']
                row['id']=self.integer(pointer)
                linked=self.integer(pointer+8)
                row['detail_index']=-1 if linked==layout['fallback'] else (linked-layout['details'])//layout['info_stride']
                if group=='stickers':row['slot_08']=int(linked!=0)
                if row['id']==0:
                    row['name']=''
                    if group=='packs':
                        row['type']=self.integer(pointer+0xc)
                        row['slots']=[dict(count=self.integer(pointer+0x14+8*slot),reward=self.integer(pointer+0x18+8*slot)) for slot in range(5)]
                    if group=='stickers':
                        row['internal']=bool(self.cpu.mem_read(pointer+0xc,1)[0])
                        row['era']=self.integer(pointer+0x10)
                        row['categories']=[self.integer(pointer+0x14+4*s) for s in range(2)]
                        row['counts']=[self.integer(pointer+0x1c+4*s) for s in range(2)]
                        if 'category' in row:row['category']=row['categories'][0]
                        if 'count' in row:row['count']=row['counts'][0]
                    if group=='cards':
                        for offset,name in [(0xc,'type'),(0x14,'reward_type'),(0x18,'category'),(0x1c,'research_needed')]:row[name]=self.integer(pointer+offset)
        return dict(records=records,registry=registry,details=details,availability=self.storage.snapshot())


def cases(content):
    result=[]
    def add(name,records=None,details=None,availability=None):
        records=records if records is not None else dict(packs=[pack(40,[(1,50)])],stickers=[sticker()],cards=[dict(card(),max_collectable=1)])
        details=details if details is not None else {group:[row['id'] for row in records[group]] for group in LAYOUT}
        result.append(dict(name=name,records=records,details=details,availability=availability or empty(),steps=2))
    add('ordinary')
    add('missing_details',details={group:[] for group in LAYOUT})
    add('duplicate_details',details=dict(packs=[40,40],stickers=[60,60],cards=[50,50]))
    for limit in [-2147483648,-1,0,1,2,2147483647]:
        add('card_limit_'+str(limit),dict(packs=[],stickers=[],cards=[dict(card(),max_collectable=limit)]))
    add('zero_rows',dict(packs=[pack(0,[(8,50)])],stickers=[dict(sticker(id=0),category=1,count=2)],cards=[dict(card(id=0),max_collectable=7)]))
    add('duplicate_data',dict(packs=[pack(40,[(1,50)]),pack(40,[(2,60)])],stickers=[sticker(),sticker(counts=[8,0])],cards=[dict(card(),max_collectable=1),dict(card(name='Other'),max_collectable=7)]))
    add('cross_group_first_capacity_wins',dict(packs=[pack(50,[])],stickers=[sticker(id=50)],cards=[dict(card(),max_collectable=1)]))
    for kind in ['stock','acquisition']:
        state=empty();state[kind+'_registered']['@50']=True;state[kind+'_limits']['@50']=7
        state['acquired']['@50']=5;state['spent']['@50']=3
        add('existing_'+kind,availability=state)
    for scope,source in content['scopes'].items():
        add('source_'+scope,dict(packs=content['packs'],stickers=content['stickers'],cards=source['cards']),content['details'])
    rng=random.Random(0xca7a10)
    for i in range(50):
        records=dict(packs=[pack(rng.choice([0,30,40]),[(rng.randrange(5),50)]) for _ in range(rng.randrange(6))],
                     stickers=[sticker(id=rng.choice([0,50,60,70])) for _ in range(rng.randrange(8))],
                     cards=[dict(card(id=rng.choice([0,50,60,70])),max_collectable=rng.choice([-1,0,1,2])) for _ in range(rng.randrange(10))])
        details={group:[rng.choice([0,30,40,50,60,70]) for _ in range(rng.randrange(8))] for group in LAYOUT}
        add('random_'+str(i),records,details)
    return result


def main():
    content=extract()
    oracle=CatalogOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_catalog()
    examples=cases(content)
    for case in examples:
        try:
            oracle.load_catalog(case)
            case['states']=[oracle.bind() for _ in range(case['steps'])]
        except Exception as error:raise ValueError('Original catalog '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    output=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],cases=examples,
                native_routines=content['native_routines'],adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_reward_catalog.json').write_text(json.dumps(output,separators=(',',':'))+'\n')
    print('Original reward catalog:',len(examples),'cases,',sum(c['steps'] for c in examples),'bindings')


if __name__=='__main__':main()
