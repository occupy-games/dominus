"""Original reward/research/era pipeline with actual acquisition dependencies.

Acquisition wrappers, dependency registration/propagation, hashes, inventory,
research and era selection execute together. Clocks, formatting/allocation,
notifications and unrelated currency/unit/effect services remain adapters.
No controlled acquisition-to-unlock mapping is supplied. Startup and the
notification service's temple/achievement/economy internals remain unported.
"""
import copy
import json

from tools.card_research import extract as research_content
from tools.current_cards import ROOT
from tools.era_progression import extract as era_content
from tools.native_availability_oracle import empty
from tools.native_era_oracle import EraOracle,state as era_state
from tools.native_era_rewards_oracle import EraRewardsOracle
from tools.native_researched_rewards_oracle import ResearchedRewardsOracle
from tools.native_unlock_dispatch_oracle import UnlockOracle,initial as unlock_state
from tools.reward_dispatch import extract as dispatch_content,key
from tools.reward_queue import extract as queue_content
from tools.sticker_selection import extract as selection_content
from tools.unlock_dispatch import extract as unlock_content


class UnlockedRewardsOracle(EraRewardsOracle):
    load_set=UnlockOracle.load_set
    load_rules=UnlockOracle.load_rules
    timer_tree=UnlockOracle.timer_tree
    new_timer=UnlockOracle.new_timer

    def configure_unlocked(self,queue,selection):
        self.configure_full_era(queue,selection)
        for handle in self.handles:self.cpu.hook_del(handle)
        del self.adapters[0x1015cc90]
        self.adapters.update({0x10356e80:self.clock_seconds,0x10179880:self.clock_millis,
                              0x1015c580:self.notify_unlock,0x1009d2e0:lambda:UnlockOracle.insert_timer(self),
                              0x10179af0:self.log_unlocked})
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        for address in [0x100242f0,0x1019a910]:self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_queue,begin=address,end=address))

    def clock_seconds(self):self.return_integer(self.step.get('clock',self.case.get('clock',dict(seconds=123,millis=[123000,0])))['seconds'])
    def clock_millis(self):
        words=self.step.get('clock',self.case.get('clock',dict(seconds=123,millis=[123000,0])))['millis']
        self.return_integer(words[0]);self.cpu.reg_write(self.regs.UC_X86_REG_EDX,words[1])
    def notify_unlock(self):self.event('notify',self.arguments(1));self.return_integer()
    def log_unlocked(self):
        channel,pointer=self.arguments(2)
        if channel!=49:return ResearchedRewardsOracle.log_researched(self)
        self.event('log',[channel,self.string(pointer),[self.arguments(3)[2]]]);self.return_integer()

    def load_unlocked(self,case,rules,dependencies):
        self.load_selected(case)
        EraOracle.load_state(self,self.GLOBAL,case.get('era_cache',era_state()))
        UnlockOracle.load(self,case.get('unlock_state',unlock_state()),rules)
        for row in dependencies:UnlockOracle.register(self,row)
        self.current_unlocks=[]
        self.events=[]

    def advance_unlocked(self,step):
        self.step=step
        if step['action']=='claim':
            self.events=[];self.storage.events=[]
            self.call(0x1015cc90,[step['id']])
            result=dict(value=True,state=self.snapshot_queue(),dispatch=self.snapshot(),availability=self.storage.snapshot(),
                        availability_events=copy.deepcopy(self.storage.events),events=copy.deepcopy(self.events),random_calls=self.random_calls,
                        research_context=EraOracle.read_state(self,self.GLOBAL))
        else:result=self.advance_full_era(step)
        result.pop('unlocks',None)
        result['unlock_state']=UnlockOracle.snapshot(self)
        return result


def cases(research,queue):
    result=[]
    def add(name,scope,steps):
        result.append(dict(name=name,scope=scope,records=dict(cards=copy.deepcopy(research['scopes'][scope]),stickers=copy.deepcopy(research['stickers']),special=copy.deepcopy(queue['special']),packs=[],stories=[]),
                           availability=empty(),era_cache=era_state(),clock=dict(seconds=123,millis=[123000,0]),
                           steps=steps,words=[0,32767,1,16384,32760,8192,25000,67]))
    def claim(name):return dict(action='claim',id=key(name))
    def reward():return [dict(action='chest',reward=key('Reward_ChestSticker')),dict(action='take',kind=1),dict(action='consume')]
    def acquire(name):return [dict(action='dispatch',reward=key(name),flags=3),dict(action='consume')]
    for scope in ['initialworldsetup6','initialworldsetup7']:
        add('authored_claims_'+scope,scope,[claim('always'),dict(action='query_era')]+reward()+[claim('TEMPLE_COMPLETE_1012'),claim('TEMPLE_COMPLETE_1020'),dict(action='query_era')])
        for card in research['scopes'][scope]:
            if card['type']!=2:continue
            add(scope+'_'+card['name'],scope,[claim('always'),dict(action='query_era')]+acquire(card['name'])+[dict(action='query_era')]+reward())
        steps=[claim('always'),dict(action='query_era')]
        for name in ['Card_Stickers_Bronze','Card_Stickers_Iron','Card_Stickers_Imperial']:
            if any(c['name']==name for c in research['scopes'][scope]):steps+=acquire(name)+[dict(action='query_era')]+reward()
        add('sequential_eras_'+scope,scope,steps)
    return result


def main():
    research=research_content();queue=queue_content();selection=selection_content();era=era_content();unlocks=unlock_content();dispatch=dispatch_content()
    oracle=UnlockedRewardsOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_unlocked(queue,selection)
    examples=cases(research,queue)
    for case in examples:
        try:
            dependencies=unlocks['scopes'][case['scope']]['dependencies']
            oracle.load_unlocked(case,unlocks['rules'],dependencies)
            case['prepared_unlocks']=UnlockOracle.snapshot(oracle)
            case['states']=[oracle.advance_unlocked(step) for step in case['steps']]
        except Exception as error:raise ValueError('Unlocked reward '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    result=dict(executable_sha256=era['executable_sha256'],source_sha256=era['source_sha256'],source_era=True,source_unlock_dispatch=True,
                native_routines={**research['native_routines'],**queue['native_routines'],**selection['native_routines'],**era['native_routines'],**dispatch['native_routines'],**unlocks['native_routines']},
                adapters=[hex(a) for a in sorted(oracle.adapters)],cases=examples,scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_unlocked_rewards.json').write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Original unlocked rewards:',len(examples),'cases,',sum(len(c['steps']) for c in examples),'transitions')


if __name__=='__main__':main()
