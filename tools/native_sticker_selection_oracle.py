"""Execute the whole original sticker selector and its weighted/count helpers.

Only current era, card completion/remaining queries, map storage and the seeded
CRT word stream are adapters. Original type/gate tests, all 256-slot scans,
owned/acquired reads, category deficits, pool ordering, rare/gem branches and
weighted draws execute. Final inventory crediting is outside this comparison.
"""
import copy
import json
import random

from tools.native_availability_oracle import AvailabilityStorage, empty
from tools.native_scenery_oracle import Oracle, ROOT
from tools.sticker_selection import CONFIG, extract


class StickerOracle(Oracle):
    def configure(self,content):
        self.content=content
        self.symbols={name:1000+i for i,name in enumerate(content['symbols'].values())}
        self.names={value:name for name,value in self.symbols.items()}
        for address,name in content['symbols'].items():self.set_integer(int(address,16),self.symbols[name])
        self.adapters={0x100f62b0:self.era,0x10026f40:self.complete,0x10027330:self.remaining,
                       0x10001360:lambda:self.storage.lookup(),0x1035f7f0:self.word}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        for address in [0x10026880,0x10026890,0x1004da90]:
            self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe,begin=address,end=address))

    def event(self,name,index,args=()):self.events.append([name,index,list(args)])
    def era(self):self.event('era',-1);self.return_integer(self.case['era'])
    def card_index(self):return (self.cpu.reg_read(self.regs.UC_X86_REG_ECX)-0x10f0b30c)//0x38
    def complete(self):
        index=self.card_index()
        self.event('card_complete',index)
        self.return_integer(int(self.case['cards'][index].get('complete',False)))
    def remaining(self):
        index=self.card_index()
        self.event('card_remaining',index)
        value=self.case['cards'][index].get('remaining',0)
        if isinstance(value,list):value=value[min(self.remaining_calls.get(index,0),len(value)-1)]
        self.remaining_calls[index]=self.remaining_calls.get(index,0)+1
        self.return_integer(value)
    def word(self):
        words=self.case.get('words',[0])
        value=words[self.calls%len(words)]
        self.calls+=1
        self.return_integer(value)
    def observe(self,cpu,address,size,user):
        pointer=cpu.reg_read(self.regs.UC_X86_REG_ECX)
        if address==0x1004da90:
            count=self.integer(pointer)
            if count>256:raise ValueError('Invalid native bag size')
            self.bags.append(dict(total=self.integer(pointer+4),entries=[dict(weight=self.integer(pointer+8+i*8),value=self.names.get(self.integer(pointer+12+i*8),self.integer(pointer+12+i*8))) for i in range(count)]))
        elif address==0x10026880:self.event('acquired',(pointer-0x10f0b30c)//0x38,[self.integer(pointer)])
        else:self.event('owned',(pointer-0x10f07ef0)//0x24,[self.integer(pointer)])

    def run_case(self,case):
        self.case=case
        self.events=[]
        self.bags=[]
        self.calls=0
        self.remaining_calls={}
        rules=copy.deepcopy(self.content['rules'])
        rules['configuration'].update(case.get('config',{}))
        for address,name in CONFIG.items():self.set_float(address,rules['configuration'][name])
        self.cpu.mem_write(0x10f0b30c,bytes(256*0x38))
        self.cpu.mem_write(0x10f07ef0,bytes(256*0x24))
        for index,card in enumerate(case['cards']):
            pointer=0x10f0b30c+index*0x38
            for offset,name in [(0,'id'),(0xc,'type'),(0x18,'category'),(0x20,'slot_20')]:self.set_integer(pointer+offset,card[name])
        for index,sticker in enumerate(case['stickers']):
            pointer=0x10f07ef0+index*0x24
            for offset,name in [(0,'id'),(8,'slot_08'),(0x10,'era'),(0x14,'category'),(0x1c,'count')]:self.set_integer(pointer+offset,sticker[name])
            self.cpu.mem_write(pointer+0xc,bytes([int(sticker['internal'])]))
        state=empty()
        for name,table in case.get('counters',{}).items():state[name].update(table)
        self.storage=AvailabilityStorage(self,state)
        kind=self.symbols.get(case['kind'],0xdeadbeef)
        result=self.call(0x1004de10,[kind,case.get('override',0)],limit=500000)
        return dict(value=self.names.get(result,result),random_calls=self.calls,events=self.events,
                    counters=self.storage.snapshot(),bags=self.bags)


def sticker(id,era=1,category=1,count=1,**extra):
    return dict(id=id,era=era,category=category,count=count,slot_08=1,internal=False,**extra)


def card(id,category=1,remaining=5,complete=False):
    return dict(id=id,type=2,slot_20=1,category=category,remaining=remaining,complete=complete)


def cases():
    basic=[sticker(10000+era*100+category,era,category) for era in range(1,5) for category in range(1,6)]
    kinds=['Reward_PrimitiveSticker','Reward_BronzeSticker','Reward_IronSticker','Reward_FrontierSticker',
           'Reward_ChestSticker','Reward_BonusChestSticker','Reward_HubworldSticker','Reward_EventSticker',
           'Reward_RandomSticker','Reward_StormChestSticker','Reward_RandomStickerOrGem','unknown']
    examples=[]
    for kind in kinds:
        for era in [0,1,2,3,4,5,0xffffffff]:
            for override in [0,1,32768,65535,65536]:
                examples.append(dict(name=f'{kind}_{era}_{override}',kind=kind,era=era,override=override,
                                     cards=[],stickers=basic,words=[32767,16384,5,27000]))
    base=dict(kind='Reward_ChestSticker',era=2,override=0,words=[0,32767,0,32767],
              cards=[card(20001,1,10),card(20002,2,20)],stickers=basic,
              counters=dict(acquired={'@20001':1}))
    for name,options in [
        ('active_need',{}),('all_need',dict(config={'StickerChance_TotallyRandomPcnt':1})),
        ('all_active',dict(counters=dict(acquired={'@20001':1,'@20002':1}))),
        ('completed',dict(cards=[card(20001,1,10,True),card(20002,2,20)])),
        ('zero_remaining',dict(cards=[card(20001,1,0),card(20002,2,0)])),
        ('negative_gate',dict(cards=[dict(card(20001),slot_20=-1)])),
        ('different_type',dict(cards=[dict(card(20001),type=1)])),
        ('owned_across_eras',dict(counters=dict(acquired={'@20001':1,'@10101':20,'@10402':30}))),
        ('spent_stock',dict(counters=dict(acquired={'@20001':1,'@10101':20},spent={'@10101':19}))),
        ('owned_underflow',dict(counters=dict(spent={'@10101':1}))),
        ('repeat_remaining',dict(cards=[card(20001,1,[5,15])])),
        ('no_stickers',dict(stickers=[])),('no_cards',dict(cards=[])),
        ('category_zero',dict(stickers=[sticker(10001,1,0)],cards=[card(20001,0,10)])),
        ('rare_excluded',dict(stickers=[sticker(10001,1,1,1000)])),
        ('rare_boundary',dict(stickers=[sticker(10001,1,1,999)])),
        ('internal_excluded',dict(stickers=[dict(sticker(10001),internal=True)])),
        ('zero_key',dict(stickers=[sticker(0)])),
        ('zero_gate',dict(stickers=[dict(sticker(10001),slot_08=0)])),
        ('final_pass_keeps_zero_gate',dict(stickers=[sticker(10001),dict(sticker(10002),slot_08=0)])),
        ('zero_era_weights',dict(config={name:0 for name in ['StickerChance_OldBeads','StickerChance_CurrentBeads','StickerChance_NewBeads','StickerChance_RareBeads']})),
        ('fractional_weights',dict(config={'StickerChance_OldBeads':.75,'StickerChance_CurrentBeads':1.75,'StickerChance_NewBeads':2.25,'StickerChance_RareBeads':.25})),
        ('fractional_chance',dict(config={'StickerChance_TotallyRandomPcnt':.3333333333})),
        ('last_slots',dict(cards=[dict(card(0),type=0) for _ in range(255)]+[card(20001)],stickers=[sticker(0) for _ in range(255)]+[sticker(10001)])),
    ]:
        example=copy.deepcopy(base)
        example.update(name=name,**copy.deepcopy(options))
        examples.append(example)
    rng=random.Random(0x4de10)
    for index in range(100):
        cards=[dict(card(20000+i,rng.randrange(6),rng.getrandbits(32),bool(rng.randrange(4)==0)),type=rng.choice([0,1,2,2,2,3]),slot_20=rng.choice([-1,0,1,1])) for i in range(rng.randrange(1,16))]
        stickers=[dict(sticker(10000+i,rng.randrange(1,5),rng.randrange(6),rng.choice([1,2,999,1000,0xffffffff])),slot_08=rng.choice([0,1,1]),internal=bool(rng.randrange(5)==0)) for i in range(rng.randrange(1,30))]
        acquired={str('@'+str(row['id'])):rng.getrandbits(32) for row in cards+stickers if rng.randrange(3)==0}
        spent={str('@'+str(row['id'])):rng.getrandbits(32) for row in stickers if rng.randrange(4)==0}
        examples.append(dict(name='mixed_'+str(index),kind=kinds[index%11],era=rng.randrange(1,5),override=0 if index%2 else rng.getrandbits(32),
                             cards=cards,stickers=stickers,counters=dict(acquired=acquired,spent=spent),words=[rng.getrandbits(32) for _ in range(6)]))
    return examples


def main():
    content=extract()
    oracle=StickerOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    oracle.configure(content)
    examples=cases()
    for case in examples:
        try:case['expected']=oracle.run_case(case)
        except Exception as error:raise ValueError('Original selector case '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    result=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],cases=examples,
                native_routines=content['native_routines'],adapters=[hex(a) for a in oracle.adapters],
                observation_hooks=['0x10026880','0x10026890','0x1004da90'],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_sticker_selection.json').write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Original sticker selection:',len(examples),'cases',flush=True)


if __name__=='__main__':main()
