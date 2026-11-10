"""Original reward pipeline with unadapted original period/sticker-era cache.

The native cache queries the actual injected unlock hash set. Unlock population
on an acquisition callback is an explicit controlled service using authored era
rows; this does not port the dependency dispatcher. Formatting, notifications,
allocation and the already documented currency/effect services remain adapters.
"""
import copy
import json

from tools.card_research import extract as research_content
from tools.current_cards import ROOT,rows,decode_archive
from tools.era_progression import extract as era_content
from tools.native_era_oracle import EraOracle,state as era_state
from tools.native_availability_oracle import empty
from tools.native_selected_rewards_oracle import SelectedRewardsOracle
from tools.reward_queue import extract as queue_content
from tools.reward_dispatch import extract as dispatch_content,key
from tools.sticker_selection import extract as selection_content


class EraRewardsOracle(SelectedRewardsOracle):
    GLOBAL=EraOracle.GLOBAL

    def configure_full_era(self,queue,selection):
        self.configure_selected(queue,selection)
        for handle in self.handles:self.cpu.hook_del(handle)
        del self.adapters[0x100f62b0]
        self.adapters.update({0x1007f4a0:lambda:EraOracle.format(self),0x100128c0:self.period_changed})
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.query_unlock,begin=0x1015c1e0,end=0x1015c1e0))
        for address in [0x100242f0,0x1019a910]:self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_queue,begin=address,end=address))

    def query_unlock(self,cpu,address,size,user):self.event('unlocked',[self.string(self.arguments(1)[0])])
    def period_changed(self):self.event('period_changed',self.arguments(1));self.return_integer()
    def with_arg(self,name):
        args=self.arguments(1)
        self.event(name,args)
        if name=='acquired':
            self.current_unlocks.extend(self.case.get('acquisition_unlocks',{}).get('@'+str(args[0]),[]))
            EraOracle.unlocks(self,self.current_unlocks)
        self.return_integer()

    def load_full_era(self,case):
        self.load_selected(case)
        EraOracle.load_state(self,self.GLOBAL,case.get('era_cache',era_state()))
        self.current_unlocks=list(case.get('unlocks',[]))
        EraOracle.unlocks(self,self.current_unlocks)

    def advance_full_era(self,step):
        self.step=step
        action=step['action']
        if action in ['query_era','set_unlocks','invalidate_era']:
            self.events=[];self.storage.events=[]
            value=True
            if action=='query_era':
                self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.GLOBAL)
                value=self.call(0x100f62b0,limit=1000000)
            elif action=='set_unlocks':
                self.current_unlocks=list(step['unlocks'])
                EraOracle.unlocks(self,self.current_unlocks)
            else:self.cpu.mem_write(self.GLOBAL,b'\0')
            result=dict(value=value,state=self.snapshot_queue(),dispatch=self.snapshot(),availability=self.storage.snapshot(),availability_events=copy.deepcopy(self.storage.events),events=copy.deepcopy(self.events),random_calls=self.random_calls)
        else:result=self.advance_researched(step)
        result['research_context']=EraOracle.read_state(self,self.GLOBAL)
        result['unlocks']=list(self.current_unlocks)
        return result


def cases(research,queue):
    result=[]
    records=dict(cards=research['scopes']['initialworldsetup6'],stickers=research['stickers'],special=queue['special'],packs=[],stories=[])
    def add(name,steps,unlocks=None,**extra):
        result.append(dict(name=name,records=copy.deepcopy(records),availability=empty(),era_cache=era_state(),
                           unlocks=unlocks or [],steps=steps,words=[0,32767,1,16384,32760,8192,25000,67],**extra))
    def reward():return [dict(action='chest',reward=key('Reward_ChestSticker')),dict(action='take',kind=1),dict(action='consume')]
    for era in range(5):add('era_'+str(era),[dict(action='query_era')]+reward()+[dict(action='query_era')],['ERA_STICKER_'+str(era)])
    for period in [0,1,2,7,12]:add('period_'+str(period),[dict(action='query_era')]+reward()+[dict(action='query_era')],['ERA_MASTER_'+str(period),'ERA_STICKER_2'])
    add('invalidated_unlock_change',[dict(action='query_era'),dict(action='set_unlocks',unlocks=['ERA_STICKER_3']),dict(action='query_era'),dict(action='invalidate_era'),dict(action='query_era')]+reward(),['ERA_STICKER_1'])
    files=decode_archive((ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes())
    for row in rows(files,'initialworldsetup6/unlocks.csv'):
        if len(row)<2 or not row[0].startswith('ERA_STICKER_') or not row[1].endswith('_COMPLETED'):continue
        identity=key(row[1].removesuffix('_COMPLETED'))
        steps=[dict(action='query_era')]+reward()+[dict(action='dispatch',reward=identity,flags=3),dict(action='consume'),dict(action='query_era')]+reward()
        add('completed_'+row[1],steps,['ERA_STICKER_1'],acquisition_unlocks={'@'+str(key(row[1])):[row[0]]})
    row=next(r for r in rows(files,'initialworldsetup7/unlocks.csv') if r and r[0]=='ERA_STICKER_4')
    identity=key(row[1].removesuffix('_COMPLETED'))
    steps=[dict(action='query_era')]+reward()+[dict(action='dispatch',reward=identity,flags=3),dict(action='consume'),dict(action='query_era')]+reward()
    add('scope7_imperial_with_prior_unlocks',steps,['ERA_STICKER_1','ERA_STICKER_2','ERA_STICKER_3'],acquisition_unlocks={'@'+str(key(row[1])):[row[0]]})
    result[-1]['records']['cards']=copy.deepcopy(research['scopes']['initialworldsetup7'])
    return result


def main():
    research=research_content();queue=queue_content();selection=selection_content();era=era_content();dispatch=dispatch_content()
    oracle=EraRewardsOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_full_era(queue,selection)
    examples=cases(research,queue)
    for case in examples:
        try:
            oracle.load_full_era(case)
            case['states']=[oracle.advance_full_era(step) for step in case['steps']]
        except Exception as error:raise ValueError('Era reward '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    content=dict(executable_sha256=era['executable_sha256'],source_sha256=era['source_sha256'],source_era=True,
                 native_routines={**research['native_routines'],**queue['native_routines'],**selection['native_routines'],**era['native_routines'],**dispatch['native_routines']},
                 adapters=[hex(a) for a in sorted(oracle.adapters)],cases=examples,scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_era_rewards.json').write_text(json.dumps(content,separators=(',',':'))+'\n')
    print('Original era rewards:',len(examples),'cases,',sum(len(c['steps']) for c in examples),'transitions')


if __name__=='__main__':main()
