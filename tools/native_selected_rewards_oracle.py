"""Original dispatch, sticker selection, research and inventory in one pipeline.

Only era context, explicit shared CRT words, tree/vector allocation, formatting,
diagnostics, notifications and unrelated domain effects are adapted. Source
selector/research helpers and fixed-map inventory storage execute unadapted.
Controlled initial counters do not establish the full startup registry yet.
"""
import copy
import json

from tools.card_research import extract as research_content
from tools.native_card_research_oracle import card,research_key,completion_key
from tools.native_availability_oracle import empty
from tools.native_researched_rewards_oracle import ResearchedRewardsOracle
from tools.native_reward_dispatch_oracle import pack
from tools.reward_dispatch import extract as dispatch_content,key
from tools.reward_queue import extract as queue_content
from tools.sticker_selection import extract as selection_content,CONFIG
from tools.native_scenery_oracle import ROOT


class SelectedRewardsOracle(ResearchedRewardsOracle):
    def call(self,address,args=(),floating=False,limit=20000000):
        # A full pack repeatedly scans all 256 card slots and runs real hash/
        # registration helpers. Keep an explicit larger instruction bound.
        return super().call(address,args,floating,limit=max(limit,12000000))

    def configure_selected(self,queue,selection):
        self.configure_researched(queue)
        for handle in self.handles:self.cpu.hook_del(handle)
        del self.adapters[0x1004de10]
        self.adapters[0x100f62b0]=self.era
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        # Acquisition reads are internal queries here, not observer services.
        for address in [0x100242f0,0x1019a910]:
            self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_queue,begin=address,end=address))
        self.selection_content=selection
        for address,name in selection['symbols'].items():self.set_integer(int(address,16),key(name))

    def era(self):self.event('era');self.return_integer(self.profile('era',1))

    def load_selected(self,case):
        self.load_researched(case)
        for address,name in CONFIG.items():self.set_float(address,case.get('configuration',{}).get(name,self.selection_content['rules']['configuration'][name]))
        for i,row in enumerate(case['records']['cards']):self.set_integer(0x10f0b30c+i*0x38+0x20,row['slot_20'])
        for i,row in enumerate(case['records']['stickers']):
            pointer=0x10f07ef0+i*0x24
            self.set_integer(pointer+8,row['slot_08'])
            self.set_integer(pointer+0x10,row['era'])


def cases(research,dispatch,queue):
    source_stickers=research['stickers']
    cards=[dict(card(category=3,research_needed=5),slot_20=1),dict(card(id=51,name='Card_Second',category=5,research_needed=7),slot_20=2)]
    kinds=['Reward_PrimitiveSticker','Reward_BronzeSticker','Reward_IronSticker','Reward_FrontierSticker','Reward_BonusChestSticker',
           'Reward_ChestSticker','Reward_HubworldSticker','Reward_EventSticker','Reward_RandomSticker','Reward_StormChestSticker','Reward_RandomStickerOrGem']
    result=[]
    def add(name,steps,rows=None,state=None,**extra):
        result.append(dict(name=name,records=dict(cards=copy.deepcopy(cards if rows is None else rows),stickers=copy.deepcopy(source_stickers),special=copy.deepcopy(queue['special']),stories=[],packs=[]),
                           availability=empty() if state is None else state,steps=steps,words=[0,32767,1,16384,32760,8192,25000,67],**extra))
    def cycle(kind,action='dispatch',override=0):
        reward=key(kind)
        first=dict(action=action,reward=reward)
        if action=='dispatch':first['override']=override
        return [first,dict(action='take',kind=1),dict(action='consume'),dict(action='consume')]
    for kind in kinds:
        for era in [0,1,2,3,4,5,0xffffffff]:
            for override in [0,1,32768,65535,65536]:
                add(f'{kind}_{era}_{override}',cycle(kind,override=override),era=era)
    state=empty()
    state['acquired']['@50']=1
    state['acquired']['@'+str(research_key(cards[0]))]=4
    first_faith=next(s for s in source_stickers if not s['internal'] and s['category']==3 and s['era']==1)
    state['acquired']['@'+str(first_faith['id'])]=1
    steps=cycle('Reward_ChestSticker','temple')+[dict(action='assign',sticker=first_faith['id']),dict(action='complete')]+cycle('Reward_ChestSticker','chest')
    add('research_changes_next_reward',steps,state=state,era=1)
    duplicate_cards=[dict(cards[0],type=1),dict(cards[0],name='Card_Last_Registered',type=2,research_needed=2)]
    add('duplicate_card_registry',[dict(action='dispatch',reward=50,flags=3),dict(action='take',kind=0),dict(action='consume')],duplicate_cards,era=1)
    state=empty();state['acquired'].update({'@50':1,'@'+str(first_faith['id']):1})
    add('duplicate_sticker_registry',[dict(action='assign',sticker=first_faith['id']),dict(action='complete')],state=state,era=1)
    result[-1]['records']['stickers'].append(dict(first_faith,counts=[5,0],count=5))
    for scope,rows in research['scopes'].items():
        for stage in [0,1,2]:
            state=empty()
            for i,row in enumerate(c for c in rows if c['type']==2):
                if stage>0 and i%3==0:
                    state['acquired']['@'+str(row['id'])]=1
                    state['acquired']['@'+str(research_key(row))]=max(0,row['research_needed']//2)
                if stage==2 and i%5==0:state['acquired']['@'+str(completion_key(row))]=1
            if stage==2:
                for i,row in enumerate(source_stickers):
                    if not row['internal']:
                        state['acquired']['@'+str(row['id'])]=i%4
                        state['spent']['@'+str(row['id'])]=min(i%4,i%3)
            steps=cycle('Reward_ChestSticker','chest')+cycle('Reward_RandomSticker','temple')+cycle('Reward_StormChestSticker','chest')
            add('source_'+scope+'_'+str(stage),steps,rows,state,era=stage+1)
    for mode in [0,1,2,3]:add('mode_'+str(mode),cycle('Reward_ChestSticker','temple'),mode=mode,era=1)
    for name,configuration in [
        ('all_active',{'StickerChance_TotallyRandomPcnt':0}),('all_needed',{'StickerChance_TotallyRandomPcnt':1}),
        ('rare',{'StickerChance_OldBeads':0,'StickerChance_CurrentBeads':0,'StickerChance_NewBeads':0,'StickerChance_RareBeads':1,'StickerChance_GemBeads':0}),
        ('gems',{'StickerChance_OldBeads':0,'StickerChance_CurrentBeads':0,'StickerChance_NewBeads':0,'StickerChance_RareBeads':0,'StickerChance_GemBeads':1}),
        ('empty',{'StickerChance_OldBeads':0,'StickerChance_CurrentBeads':0,'StickerChance_NewBeads':0,'StickerChance_RareBeads':0,'StickerChance_GemBeads':0})]:
        add('configuration_'+name,cycle('Reward_RandomStickerOrGem','chest')*3,state=copy.deepcopy(state),configuration=configuration,era=1)
    source_packs=[]
    for row in dispatch['tables']['initialworldsetup/packdata.csv'][1:]:
        if not row or not row[0].startswith('Pack_'):continue
        source_packs.append(pack(key(row[0]),[(int(row[4+2*i] or 0),key(row[5+2*i])) for i in range(5)]))
    for row,definition in zip([r for r in dispatch['tables']['initialworldsetup/packdata.csv'][1:] if r and r[0].startswith('Pack_')],source_packs):
        count=sum(max(0,s['count']) for s in definition['slots'])
        # Both kinds are collected so original resource cards and stickers are
        # redeemed together, preserving the queue's last-in-first-out order.
        steps=[dict(action='temple',reward=definition['id'])]
        steps.extend([dict(action='take',kind=k) for k in [0,1]]*count)
        steps.extend([dict(action='consume')]*(count+1))
        add('pack_'+row[0],steps,research['scopes']['initialworldsetup6'],era=2)
        result[-1]['records']['packs']=source_packs
    return result


def main():
    research=research_content();selection=selection_content();queue=queue_content();dispatch=dispatch_content()
    oracle=SelectedRewardsOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_selected(queue,selection)
    examples=cases(research,dispatch,queue)
    for case in examples:
        try:
            oracle.load_selected(case)
            case['states']=[oracle.advance_researched(step) for step in case['steps']]
        except Exception as error:raise ValueError('Selected reward '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    content=dict(executable_sha256=research['executable_sha256'],source_sha256=research['source_sha256'],
                 native_routines={**queue['native_routines'],**research['native_routines'],**selection['native_routines'],**dispatch['native_routines']},
                 adapters=[hex(a) for a in sorted(oracle.adapters)],cases=examples,scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_selected_rewards.json').write_text(json.dumps(content,separators=(',',':'))+'\n')
    print('Original selected rewards:',len(examples),'cases,',sum(len(c['steps']) for c in examples),'transitions')


if __name__=='__main__':main()
