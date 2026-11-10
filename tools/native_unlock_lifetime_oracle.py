"""Execute original persistent-claim rebuild and temporary-claim expiry.

The complete 0x1015cdb0 rebuild and 0x1015cf20 expiry routines execute with actual
claim propagation, map/set insertion and tree iteration. Explicit clocks,
effect/configuration reset delivery, notification delivery, and timer-tree
allocation/removal/deallocation are adapters. No host OS or entrypoint executes.
"""
import copy
import json
import random

from tools.current_cards import ROOT
from tools.native_unlock_dispatch_oracle import UnlockOracle,initial,pair
from tools.reward_dispatch import key
from tools.unlock_dispatch import extract


class LifetimeOracle(UnlockOracle):
    def configure_lifetime(self):
        self.configure_unlocks()
        for handle in self.handles:self.cpu.hook_del(handle)
        self.adapters.update({0x1015bd70:lambda:self.reset('reset_modifiers'),0x10172220:lambda:self.reset('reset_configuration'),
                              0x10356e80:self.seconds,0x103532e0:self.remove_timer,0x103571c0:lambda:self.return_integer()})
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def reset(self,name):self.events.append([name,[]]);self.return_integer()
    def seconds(self):self.return_integer(self.step.get('seconds',123))
    def remove_timer(self):
        node,root,left,right=self.arguments(4)
        identity=self.integer(node+16)
        count=self.integer(0x10cfb770)
        del self.timer_nodes[identity]
        self.timer_tree()
        self.set_integer(0x10cfb770,count) # The original caller decrements it.
        self.return_integer(node)

    def advance(self,step):
        if step['action'] not in ['rebuild','expire']:return super().advance(step)
        self.step=step;self.events=[]
        if step['action']=='rebuild':self.call(0x1015cdb0)
        else:self.call(0x1015cf20,[int(step.get('force',False))])
        if self.integer(0x10cfb770)!=len(self.timer_nodes):raise ValueError('Original timer count differs from storage')
        return dict(value=True,state=self.snapshot(),events=copy.deepcopy(self.events))


def cases(content):
    result=[]
    def row(u,c,p=1):return dict(unlock=u,condition=c,phase=p)
    def add(name,state=None,dependencies=None,steps=None,**extra):
        state=state or initial();state['first_seen_order']=list(state['first_seen'])
        result.append(dict(name=name,state=state,dependencies=dependencies or [],steps=steps or [],**extra))
    def expire(now=None,force=False):return dict(action='expire',seconds=123,now=now or [1000,0],force=force)
    add('empty',steps=[expire(),expire(force=True),dict(action='rebuild',seconds=456,now=[9000,0])])
    s=initial();s['first_seen']={'@2058':11,'@10':22,'@1034':33,'@9':44}
    for name in ['registered','unlocked','propagated','received']:s[name]={'@999':True}
    add('bucket_chain_replay_order',s,[row(100,2058),row(101,10),row(102,1034),row(103,9)],steps=[dict(action='rebuild',seconds=999,now=[9000,0]),dict(action='rebuild',seconds=1000,now=[9001,0])])
    for phase in [0,1,2,3,0xffffffff]:
        s=initial();s['first_seen']={'@10':40}
        add('reset_phase_'+str(phase),s,[row(20,10,phase),row(30,20)],steps=[dict(action='rebuild'),dict(action='rebuild')])
    for deadline in [[999,0],[1000,0],[1001,0],[0xffffffff,0],[0,1],[0,0x80000000],[0xffffffff,0xffffffff]]:
        s=initial();s['timers']={'@10':deadline};s['unlocked']={'@20':True};s['propagated']={'@20':True}
        add('boundary_'+str(deadline),s,[row(20,10)],steps=[expire(),expire(force=True),expire([0xffffffff,0xffffffff])])
    s=initial();s['first_seen']={'@1':7};s['timers']={'@30':[1,0],'@10':[1000,0],'@20':[3,0]}
    s['unlocked']={'@11':True,'@21':True,'@31':True}
    add('one_expiry_per_call_in_key_order',s,[row(2,1),row(11,10),row(21,20),row(31,30)],[expire(),expire(),expire(),expire()])
    s=initial();s['timers']={'@10':[1001,0],'@20':[999,0],'@30':[999,0]}
    add('skip_unexpired_lower_key',s,[row(11,10),row(21,20),row(31,30)],[expire(),expire(),expire()])
    s=initial();s['first_seen']={'@10':1,'@20':2};s['timers']={'@10':[1,0]}
    rules=copy.deepcopy(content['rules']);rules['dynamic_claims'][0]=dict(id=10,seconds=3)
    add('persistent_replay_can_recreate_dynamic_timer',s,[row(11,10),row(21,20)],[expire(),expire([4000,0]),expire([8000,0])],rules=rules)
    s=initial();s['first_seen']={'@10':1,'@'+str(pair(10,20)):2}
    add('compound_phase_reset_after_replay',s,[row(20,10,0),row(30,20)],[dict(action='rebuild'),dict(action='rebuild')])
    for scope,source in content['scopes'].items():
        s=initial();names=['always','Card_Stickers_Bronze_COMPLETED','Card_Stickers_Iron_COMPLETED','TEMPLE_COMPLETE_1012']
        s['first_seen']={'@'+str(key(name)):i+1 for i,name in enumerate(names)}
        seasonal=content['rules']['dynamic_claims'][:3]
        s['timers']={'@'+str(r['id']):[1000+i,0] for i,r in enumerate(seasonal)}
        add('authored_'+scope,s,source['dependencies'],[expire(),expire(),expire(),expire(),expire(force=True)])
    rng=random.Random(0x1015cf20)
    for i in range(64):
        s=initial()
        for j in rng.sample(range(10,25),rng.randrange(10)):s['first_seen']['@'+str(j)]=rng.randrange(1000)
        for j in rng.sample(range(10,25),rng.randrange(8)):s['timers']['@'+str(j)]=[rng.randrange(3000),rng.randrange(2)]
        dependencies=[row(u,c,rng.randrange(4)) for u in range(11,25) for c in range(10,u) if rng.randrange(12)==0]
        add('random_'+str(i),s,dependencies,[expire([1000,0]),expire([2000,0]),expire([0,1]),expire([3000,1]),expire(force=True)])
    return result


def main():
    content=extract();oracle=LifetimeOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_lifetime()
    examples=cases(content)
    for case in examples:
        try:
            rules=case.get('rules',content['rules']);oracle.load(case['state'],rules)
            for row in case['dependencies']:oracle.register(row)
            case['prepared']=oracle.snapshot()
            case['states']=[oracle.advance(step) for step in case['steps']]
            current=case['prepared']
            for step,expected in zip(case['steps'],case['states']):
                oracle.load(current,rules);actual=oracle.advance(step)
                if actual!=expected:raise ValueError('Native restored lifetime differs')
                current=actual['state']
        except Exception as error:raise ValueError('Original unlock lifetime '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    result=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],native_routines=content['native_routines'],
                adapters=[hex(a) for a in sorted(oracle.adapters)],cases=examples,scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_unlock_lifetime.json').write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Original unlock lifetime:',len(examples),'cases,',sum(len(c['steps']) for c in examples),'transitions')


if __name__=='__main__':main()
