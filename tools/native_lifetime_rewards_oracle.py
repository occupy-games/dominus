"""Original reward/research/era pipeline through temporal unlock rebuilds.

Actual claim expiry and persistent replay execute inside the same original
reward, inventory and era state. Clocks, reset effect/configuration services,
notifications and already documented allocation/currency/unit/effect services
are adapters. This is not whole application startup or configuration effects.
"""
import copy
import json

from tools.card_research import extract as research_content
from tools.current_cards import ROOT
from tools.era_progression import extract as era_content
from tools.native_availability_oracle import empty
from tools.native_era_oracle import EraOracle,state as era_state
from tools.native_unlock_dispatch_oracle import UnlockOracle
from tools.native_unlock_lifetime_oracle import LifetimeOracle
from tools.native_unlocked_rewards_oracle import UnlockedRewardsOracle
from tools.reward_dispatch import extract as dispatch_content,key
from tools.reward_queue import extract as queue_content
from tools.sticker_selection import extract as selection_content
from tools.unlock_dispatch import extract as unlock_content


class LifetimeRewardsOracle(UnlockedRewardsOracle):
    def configure_lifetime_rewards(self,queue,selection):
        self.configure_unlocked(queue,selection)
        for handle in self.handles:self.cpu.hook_del(handle)
        self.adapters.update({0x1015bd70:lambda:self.reset_effects('reset_modifiers'),0x10172220:lambda:self.reset_effects('reset_configuration'),
                              0x103532e0:lambda:LifetimeOracle.remove_timer(self),0x103571c0:lambda:self.return_integer()})
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        for address in [0x100242f0,0x1019a910]:self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_queue,begin=address,end=address))

    def reset_effects(self,name):self.event(name);self.return_integer()

    def advance_unlocked(self,step):
        if step['action']!='expire':return super().advance_unlocked(step)
        self.step=step;self.events=[];self.storage.events=[]
        self.call(0x1015cf20,[int(step.get('force',False))])
        if self.integer(0x10cfb770)!=len(self.timer_nodes):raise ValueError('Original lifetime timer count differs')
        return dict(value=True,state=self.snapshot_queue(),dispatch=self.snapshot(),availability=self.storage.snapshot(),
                    availability_events=copy.deepcopy(self.storage.events),events=copy.deepcopy(self.events),random_calls=self.random_calls,
                    research_context=EraOracle.read_state(self,self.GLOBAL),unlock_state=UnlockOracle.snapshot(self))


def cases(research,queue,unlocks):
    result=[]
    dynamic=[r['id'] for r in unlocks['rules']['dynamic_claims'] if r['seconds']>0]
    def add(name,scope,steps):
        result.append(dict(name=name,scope=scope,records=dict(cards=copy.deepcopy(research['scopes'][scope]),stickers=copy.deepcopy(research['stickers']),special=copy.deepcopy(queue['special']),packs=[],stories=[]),
                           availability=empty(),era_cache=era_state(),clock=dict(seconds=123,millis=[123000,0]),steps=steps,
                           words=[0,32767,1,16384,32760,8192,25000,67]))
    def claim(id):return dict(action='claim',id=id)
    def expire(now=604923000,force=False):return dict(action='expire',force=force,clock=dict(seconds=now//1000,millis=[now,0]))
    def reward():return [dict(action='chest',reward=key('Reward_ChestSticker')),dict(action='take',kind=1),dict(action='consume')]
    def acquire(name):return [dict(action='dispatch',reward=key(name),flags=3),dict(action='consume')]
    for scope in ['initialworldsetup6','initialworldsetup7']:
        add('seasonal_expiry_'+scope,scope,[claim(key('always')),claim(dynamic[0]),claim(dynamic[1]),dict(action='query_era'),
                                            expire(604922999),expire(),dict(action='query_era'),expire(),dict(action='query_era')]+reward())
        advance='Card_Stickers_Bronze' if scope=='initialworldsetup6' else 'Card_Stickers_Imperial'
        add('research_and_rebuild_'+scope,scope,[claim(key('always'))]+acquire(advance)+[dict(action='query_era'),expire(123000,True),dict(action='query_era')]+reward()+[expire(123000,True),dict(action='query_era')])
        steps=[claim(key('always'))]+[claim(id) for id in dynamic]
        for i in range(len(dynamic)):steps+=[expire(),dict(action='query_era')]
        add('ten_temporary_claims_'+scope,scope,steps+[expire()]+reward())
    return result


def main():
    research=research_content();queue=queue_content();selection=selection_content();era=era_content();unlocks=unlock_content();dispatch=dispatch_content()
    oracle=LifetimeRewardsOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_lifetime_rewards(queue,selection)
    examples=cases(research,queue,unlocks)
    for case in examples:
        try:
            oracle.load_unlocked(case,unlocks['rules'],unlocks['scopes'][case['scope']]['dependencies'])
            case['prepared_unlocks']=UnlockOracle.snapshot(oracle)
            case['states']=[oracle.advance_unlocked(step) for step in case['steps']]
        except Exception as error:raise ValueError('Lifetime rewards '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    result=dict(executable_sha256=era['executable_sha256'],source_sha256=era['source_sha256'],source_era=True,source_unlock_dispatch=True,
                native_routines={**research['native_routines'],**queue['native_routines'],**selection['native_routines'],**era['native_routines'],**dispatch['native_routines'],**unlocks['native_routines']},
                adapters=[hex(a) for a in sorted(oracle.adapters)],cases=examples,scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_lifetime_rewards.json').write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Original lifetime rewards:',len(examples),'cases,',sum(len(c['steps']) for c in examples),'transitions')


if __name__=='__main__':main()
