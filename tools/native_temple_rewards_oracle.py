"""Actual temple markers and deferred discovery rewards in shared source state.

The original 0x1015cd60 marker wrapper, inventory registration/acquisition,
dependency dispatch, deferred discovery branch, reward selection and redemption
execute together. Clocks, notification/effect delivery and documented storage/
formatting services remain adapters. Other temple types and worker/lifecycles
are not established by this deferred-reward comparison.
"""
import copy
import json

from tools.card_research import extract as research_content
from tools.current_cards import ROOT
from tools.era_progression import extract as era_content
from tools.native_availability_oracle import empty
from tools.native_era_oracle import EraOracle,state as era_state
from tools.native_lifetime_rewards_oracle import LifetimeRewardsOracle
from tools.native_reward_dispatch_oracle import DispatchOracle
from tools.native_temple_repair_oracle import state as temple_state
from tools.native_unlock_dispatch_oracle import UnlockOracle,initial as unlock_state
from tools.reward_dispatch import extract as dispatch_content,key
from tools.reward_queue import extract as queue_content
from tools.sticker_selection import extract as selection_content
from tools.unlock_dispatch import extract as unlock_content


class TempleRewardsOracle(LifetimeRewardsOracle):
    def configure_temple_rewards(self,queue,selection):
        self.configure_lifetime_rewards(queue,selection)
        for handle in self.handles:self.cpu.hook_del(handle)
        del self.adapters[0x1015cd60]
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        for address in [0x100242f0,0x1019a910]:self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_queue,begin=address,end=address))
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_temple,begin=0x1003af00,end=0x1003af00))

    def observe_temple(self,cpu,address,size,user):self.event('is_discovery')

    def format(self):
        output,template,value=self.arguments(3)
        if self.string(template)!='TEMPLE_COMPLETE_%d':return super().format()
        if value>=0x80000000:value-=0x100000000
        text='TEMPLE_COMPLETE_%d'%value
        self.cpu.mem_write(output,text.encode()+b'\0');self.return_integer(len(text))

    def load_temple_rewards(self,case,rules,dependencies,dispatch):
        self.load_unlocked(case,rules,dependencies)
        self.temple_site=self.POOL+0x5000
        self.cpu.mem_write(self.temple_site,bytes(0x43c))
        for name,offset in [('phase',0x2fc),('source_id',0x10),('reward_pending',0x238),('reward',0x234)]:self.set_integer(self.temple_site+offset,case['temple'][name])
        self.cpu.mem_write(self.temple_site+0x2c0,bytes([int(case['temple']['reward_ready'])]))
        self.set_integer(0x107d1af0,1);self.set_integer(0x107d1aec,dispatch['rules']['discovery_type'])
        self.set_integer(self.temple_site+0x30c,dispatch['rules']['discovery_type'] if case.get('is_discovery',True) else 0xdeadbeef)

    def advance_unlocked(self,step):
        self.step=step
        if step['action'] not in ['force_unlock','temple_pending']:
            result=super().advance_unlocked(step)
        else:
            self.events=[];self.storage.events=[]
            if step['action']=='force_unlock':value=bool(self.call(0x1015cd60,[step['id']])&255)
            else:
                value=bool(self.case.get('is_discovery',True) and self.integer(self.temple_site+0x238))
                frame=self.STACK+0x80000
                self.cpu.reg_write(self.regs.UC_X86_REG_ESP,frame-0x200)
                self.cpu.reg_write(self.regs.UC_X86_REG_EBP,frame)
                self.cpu.reg_write(self.regs.UC_X86_REG_ESI,self.temple_site)
                self.cpu.reg_write(self.regs.UC_X86_REG_EBX,0)
                self.cpu.emu_start(0x10140b9c,0x10140c0f,count=20000000)
                if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=0x10140c0f:raise ValueError('Deferred source temple budget exhausted')
            result=dict(value=value,state=self.snapshot_queue(),dispatch=self.snapshot(),availability=self.storage.snapshot(),
                        availability_events=copy.deepcopy(self.storage.events),events=copy.deepcopy(self.events),random_calls=self.random_calls,
                        research_context=EraOracle.read_state(self,self.GLOBAL),unlock_state=UnlockOracle.snapshot(self))
        result['temple']=DispatchOracle.temple_snapshot(self)
        return result


def cases(research,queue,dispatch):
    result=[]
    sites=json.loads((ROOT/'game/assets/original/campaign/temple-sites.json').read_text())['scopes']['initialworldsetup6']
    def add(name,steps,temple=None,**extra):
        temple=temple or temple_state();temple['reward']=temple['reward'] if isinstance(temple['reward'],int) else key(temple['reward'])
        result.append(dict(name=name,scope='initialworldsetup6',records=dict(cards=copy.deepcopy(research['scopes']['initialworldsetup6']),stickers=copy.deepcopy(research['stickers']),special=copy.deepcopy(queue['special']),packs=[],stories=[]),
                           availability=empty(),era_cache=era_state(),clock=dict(seconds=123,millis=[123000,0]),steps=steps,temple=temple,
                           words=[0,32767,1,16384,32760,8192,25000,67],**extra))
    for site in sites:
        identity=key('TEMPLE_COMPLETE_'+site['id'])
        add('marker_'+site['id'],[dict(action='force_unlock',id=identity),dict(action='force_unlock',id=identity),dict(action='expire',force=True),dict(action='force_unlock',id=identity)])
    marker=key('TEMPLE_COMPLETE_1012')
    for registered,unlocked in [(False,False),(True,False),(True,True)]:
        state=unlock_state()
        if registered:state['registered']['@'+str(marker)]=True
        if unlocked:state['unlocked']['@'+str(marker)]=True
        add('gate_'+str(registered)+'_'+str(unlocked),[dict(action='force_unlock',id=marker)]*2,unlock_state=state)
    for limit in [0,1,4]:
        for acquired in [0,1,4]:
            add(f'capacity_{limit}_{acquired}',[dict(action='force_unlock',id=marker)]*2)
            result[-1]['availability'].update(stock_registered={'@'+str(marker):True},acquisition_registered={'@'+str(marker):True},
                                              stock_limits={'@'+str(marker):limit},acquisition_limits={'@'+str(marker):limit},acquired={'@'+str(marker):acquired})
    for identity in [0,0xffffffff]:add('numeric_'+str(identity),[dict(action='force_unlock',id=identity)]*2)
    for row in dispatch['tables']['initialworldsetup/packdata.csv'][1:]:
        if not row or not row[0].startswith('Pack_'):continue
        temple=temple_state();temple.update(source_id=1100,reward=key(row[0]),reward_pending=1,reward_ready=True,phase=7)
        add('pending_'+row[0],[dict(action='claim',id=key('always')),dict(action='temple_pending'),dict(action='temple_pending'),dict(action='take',kind=0),dict(action='take',kind=1),dict(action='consume'),dict(action='query_era')],temple)
        from tools.native_reward_dispatch_oracle import pack
        result[-1]['records']['packs']=[pack(key(r[0]),[(int(r[4+2*i] or 0),key(r[5+2*i])) for i in range(5)]) for r in dispatch['tables']['initialworldsetup/packdata.csv'][1:] if r and r[0].startswith('Pack_')]
    for name,changes,extra in [('no_pending',dict(reward_pending=0),{}),('not_discovery',dict(reward_pending=1),dict(is_discovery=False)),('zero_reward',dict(reward_pending=1,reward=0),{}),('blocked_phase',dict(phase=8,reward_pending=1,reward_ready=False),{})]:
        temple=temple_state();temple.update(changes)
        add(name,[dict(action='temple_pending')]*2,temple,**extra)
    return result


def main():
    research=research_content();queue=queue_content();selection=selection_content();era=era_content();unlocks=unlock_content();dispatch=dispatch_content()
    oracle=TempleRewardsOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_temple_rewards(queue,selection)
    examples=cases(research,queue,dispatch)
    for case in examples:
        try:
            oracle.load_temple_rewards(case,unlocks['rules'],unlocks['scopes'][case['scope']]['dependencies'],dispatch)
            case['prepared_unlocks']=UnlockOracle.snapshot(oracle)
            case['states']=[oracle.advance_unlocked(step) for step in case['steps']]
        except Exception as error:raise ValueError('Temple rewards '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    result=dict(executable_sha256=era['executable_sha256'],source_sha256=era['source_sha256'],source_era=True,source_unlock_dispatch=True,source_temple=True,
                native_routines={**research['native_routines'],**queue['native_routines'],**selection['native_routines'],**era['native_routines'],**dispatch['native_routines'],**unlocks['native_routines']},
                adapters=[hex(a) for a in sorted(oracle.adapters)],cases=examples,scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_temple_rewards.json').write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Original temple rewards:',len(examples),'cases,',sum(len(c['steps']) for c in examples),'transitions')


if __name__=='__main__':main()
