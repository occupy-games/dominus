"""Execute original unlock registration, propagation, claims and timer queries.

Hashes, fixed set/map insertion, dependency traversal, float conversion and
deadline arithmetic execute. Notification/log delivery, explicit clocks and
ordered timer-tree allocation are adapters. No entrypoint or host OS executes.
"""
import copy
import json
import random
import struct

from tools.current_cards import ROOT
from tools.native_scenery_oracle import Oracle
from tools.reward_dispatch import key
from tools.unlock_dispatch import extract

SETS=dict(registered=0x10c98758,unlocked=0x10cb9760,propagated=0x10cda768,received=0x10cfb790)


def initial():return dict(rows=[],registered={},unlocked={},propagated={},received={},first_seen={},first_seen_order=[],timers={})


class UnlockOracle(Oracle):
    def configure_unlocks(self):
        self.adapters={0x1015c580:self.notify,0x10179af0:self.log,0x10179880:self.clock,
                       0x1009d2e0:self.insert_timer,
                       0x1035f830:lambda:self.return_integer(self.cpu.reg_read(self.regs.UC_X86_REG_EAX))}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def notify(self):self.events.append(['notify',self.arguments(1)]);self.return_integer()
    def log(self):
        channel,pointer,identity=self.arguments(3)
        text=bytes(self.cpu.mem_read(pointer,100)).split(b'\0')[0].decode()
        self.events.append(['log',[channel,text,[identity]]]);self.return_integer()
    def clock(self):
        self.return_integer(self.step.get('now',[0,0])[0])
        self.cpu.reg_write(self.regs.UC_X86_REG_EDX,self.step.get('now',[0,0])[1])

    def timer_tree(self):
        header=self.POOL+0x30000
        self.cpu.mem_write(header,bytes(32));self.set_integer(0x10cfb76c,header)
        self.set_integer(header+8,header);self.set_integer(header+12,header)
        ids=sorted(self.timer_nodes)
        def build(lo,hi,parent):
            if lo>=hi:return 0
            mid=(lo+hi)//2;node=self.timer_nodes[ids[mid]]
            self.set_integer(node+4,parent)
            self.set_integer(node+8,build(lo,mid,node));self.set_integer(node+12,build(mid+1,hi,node))
            return node
        self.set_integer(header+4,build(0,len(ids),header))
        if ids:self.set_integer(header+8,self.timer_nodes[ids[0]]);self.set_integer(header+12,self.timer_nodes[ids[-1]])
        self.set_integer(0x10cfb770,len(ids))

    def new_timer(self,id,words):
        node=self.timer_heap;self.timer_heap+=0x40
        self.timer_nodes[id]=node;self.cpu.mem_write(node,bytes(32))
        self.set_integer(node+16,id)
        self.set_integer(node+24,words[0]);self.set_integer(node+28,words[1]);self.timer_tree()
        return node

    def insert_timer(self):
        result,hint,record=self.arguments(3)
        identity=self.integer(record)
        node=self.new_timer(identity,[self.integer(record+8),self.integer(record+12)])
        self.set_integer(result,node);self.return_integer(result,pop=12)

    def load_set(self,base,values):
        self.cpu.mem_write(base+0x20000,bytes(1024*4));self.set_integer(base+0x21000,0)
        for identity in values:
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,base)
            self.call(0x1015c0d0,[int(identity[1:])])

    def load(self,state,rules):
        self.events=[];self.timer_nodes={};self.timer_heap=self.POOL+0x40000
        for name,base in SETS.items():self.load_set(base,state[name])
        self.cpu.mem_write(0x10d4c798,bytes(1024*4));self.set_integer(0x10d4d798,0)
        for identity in state.get('first_seen_order',list(state['first_seen'])):
            time=state['first_seen'][identity]
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,0x10d1c798)
            self.call(0x1015bcb0,[int(identity[1:]),time])
        self.timer_tree()
        for identity,words in state['timers'].items():self.new_timer(int(identity[1:]),words)
        self.vector=self.GRIDS
        self.set_integer(0x10c9874c,self.vector);self.set_integer(0x10c98750,self.vector)
        self.set_integer(0x10c98754,self.vector+16384*16)
        for i,row in enumerate(state['rows']):
            self.cpu.mem_write(self.vector+i*16,struct.pack('<4I',*[row[k] for k in ('unlock','condition','compound','phase')]))
        self.set_integer(0x10c98750,self.vector+len(state['rows'])*16)
        self.load_rules(rules)

    def load_rules(self,rules):
        for i,row in enumerate(rules['dynamic_claims']):
            self.set_integer(0x10fbdfe8+i*8,row['id']);self.set_integer(0x10fbdfec+i*8,row['seconds'])

    def snapshot(self):
        result=initial()
        for name,base in SETS.items():
            result[name]={'@'+str(self.integer(base+i*8)):True for i in range(self.integer(base+0x21000))}
        result['first_seen']={'@'+str(self.integer(0x10d1c798+i*12)):self.integer(0x10d1c79c+i*12) for i in range(self.integer(0x10d4d798))}
        result['first_seen_order']=list(result['first_seen'])
        for identity,node in self.timer_nodes.items():result['timers']['@'+str(identity)]=[self.integer(node+24),self.integer(node+28)]
        count=(self.integer(0x10c98750)-self.vector)//16
        for i in range(count):result['rows'].append(dict(zip(('unlock','condition','compound','phase'),struct.unpack('<4I',self.cpu.mem_read(self.vector+i*16,16)))))
        return result

    def register(self,row):
        if 'unlock_name' in row:
            first=self.SCRATCH+0x2000;second=self.SCRATCH+0x2800
            self.cpu.mem_write(first,row['unlock_name'].encode()+b'\0');self.cpu.mem_write(second,row['condition_name'].encode()+b'\0')
            self.call(0x1015c9e0,[first,second,row['phase']])
        else:self.call(0x1015c710,[row['unlock'],row['condition'],row['phase']])

    def advance(self,step):
        self.step=step;self.events=[];action=step['action'];value=True
        self.set_integer(0x11181508,int(step.get('sse2',False)))
        if action=='register':self.register(step)
        elif action=='claim':self.call(0x1015c7f0,[step['id'],step.get('seconds',0)])
        elif action=='propagate':self.call(0x1015c640,[step['id']])
        elif action=='remaining':value=struct.unpack('<i',struct.pack('<I',self.call(0x1015c270,[step['id']])))[0]
        elif action=='unlocked':value=bool(self.call(0x1015c130,[step['id']])&255)
        elif action=='can_unlock':value=bool(self.call(0x1015c170,[step['id']])&255)
        else:raise ValueError(action)
        return dict(value=value,state=self.snapshot(),events=copy.deepcopy(self.events))


def pair(a,b):
    from tools.card_research import pair_key
    return pair_key(a,b)


def cases(content):
    result=[]
    def add(name,dependencies=None,steps=None,state=None,**extra):
        if state is not None:state['first_seen_order']=list(state['first_seen'])
        result.append(dict(name=name,state=state or initial(),dependencies=dependencies or [],steps=steps or [],**extra))
    def row(u,c,p=1):return dict(unlock=u,condition=c,phase=p)
    def claim(id,seconds=1,now=None):return dict(action='claim',id=id,seconds=seconds,now=now or [0,0])
    def query(id,action='unlocked'):return dict(action=action,id=id)
    add('empty',steps=[query(0),query(1,'can_unlock'),claim(0),claim(0,99),query(0),query(0,'remaining')])
    add('depth_first_repeated', [row(20,10),row(30,20),row(40,10),row(30,40)], [claim(10),claim(10,99),query(30)])
    add('compound_condition_first',[row(20,10,0),row(30,20)],[claim(10),claim(pair(10,20)),claim(10,99)])
    add('compound_activation_first',[row(20,10,0),row(30,20)],[claim(pair(10,20)),claim(10),claim(pair(10,20))])
    add('compound_unreceived_propagation',[row(20,10,0)],[dict(action='propagate',id=10),claim(pair(10,20)),claim(10)])
    for old in [0,1,2,3,0xffffffff]:
        for new in [0,1,2,3,0xffffffff]:
            add(f'register_{old}_{new}',[row(20,10,old)],[dict(action='register',**row(20,10,new)),claim(10),claim(pair(10,20)),claim(10)])
    s=initial();s['registered']={'@20':True,'@30':True};s['unlocked']={'@30':True}
    add('registered_and_unlocked_are_distinct',[row(20,10)],[query(20,'can_unlock'),query(30,'can_unlock'),query(40,'can_unlock'),claim(10),query(20),query(20,'can_unlock')],s)
    for seconds in [-2147483648,-1,0,1,604800,16777217,2147483647]:
        rules=copy.deepcopy(content['rules']);rules['dynamic_claims'][0]=dict(id=10,seconds=seconds)
        add('duration_'+str(seconds),[row(20,10),row(30,10,0)],
            [claim(10,123,[0xfffffff0,0xffffffff]),query(10,'remaining'),claim(pair(10,30)),claim(10,456,[50,1]),dict(action='remaining',id=10,now=[51,1])],rules=rules)
    rules=copy.deepcopy(content['rules']);rules['dynamic_claims'][:2]=[dict(id=10,seconds=0),dict(id=10,seconds=5)]
    add('first_dynamic_row_wins',[row(20,10)],[claim(10),query(10,'remaining')],rules=rules)
    dynamic=[r['id'] for r in content['rules']['dynamic_claims'] if r['seconds']>0]
    steps=[claim(id,123,[0xfffffff0+i,1]) for i,id in enumerate(dynamic)]
    steps.extend(dict(action='remaining',id=id,now=[40,2]) for id in dynamic)
    steps.extend([claim(dynamic[0],456,[0xabcdef01,8]),dict(action='remaining',id=dynamic[0],now=[0xabcdef01,8])])
    add('authored_dynamic_claims',[row(20,dynamic[0]),row(30,dynamic[1])],steps)
    for now in [[0,0],[1,0],[999,0],[1000,0],[1001,0],[0xffffffff,0],[0,1],[0xffffffff,0x7fffffff],[0,0x80000000],[0xffffffff,0xffffffff]]:
        s=initial();s['timers']={'@10':[1000,0]}
        for sse2 in [False,True]:
            add(('remaining_sse2_' if sse2 else 'remaining_')+str(now),steps=[dict(action='remaining',id=10,now=now,sse2=sse2)],state=s)
    for deadline in [[0xffffffff,499],[0,500],[1000,500]]:
        s=initial();s['timers']={'@10':deadline}
        for sse2 in [False,True]:
            add('overflow_'+str(deadline)+'_'+str(sse2),steps=[dict(action='remaining',id=10,now=[0,0],sse2=sse2)],state=s)
    for scope,source in content['scopes'].items():
        dependencies=[dict(**row(d['unlock'],d['condition']),unlock_name=b['unlock'],condition_name=b['condition']) for d,b in zip(source['dependencies'],source['bindings'])]
        names=['always','Card_Stickers_Bronze_COMPLETED','Card_Stickers_Iron_COMPLETED','Card_Stickers_Imperial_COMPLETED','TEMPLE_COMPLETE_1012','TEMPLE_COMPLETE_1020','Card_Adv_GodSeed_1']
        add('authored_'+scope,dependencies,[claim(key(name),i+100) for i,name in enumerate(names)]+[query(key('ERA_STICKER_'+str(i))) for i in range(1,5)])
    s=initial()
    s['first_seen']={'@'+str(100000+i):i for i in range(16384)};s['received']={k:True for k in s['first_seen']}
    add('received_capacity',[row(20,10,0)],[claim(10),claim(pair(10,20)),claim(10)],state=s)
    s=initial();s['unlocked']={'@'+str(100000+i):True for i in range(16384)};s['propagated']=dict(s['unlocked'])
    add('unlock_capacity_still_recurses',[row(20,10),row(30,20)],[claim(10),query(20)],state=s)
    rng=random.Random(0x1015c640)
    for i in range(80):
        dependencies=[row(u,c,rng.choice([0,1,2,3])) for u in range(11,25) for c in range(10,u) if rng.randrange(9)==0]
        steps=[]
        for j in range(8):
            id=rng.randrange(10,25)
            if dependencies and rng.randrange(3)==0:
                r=rng.choice(dependencies);id=pair(r['condition'],r['unlock'])
            steps.append(claim(id,rng.randrange(0xffffffff)))
        add('random_'+str(i),dependencies,steps)
    return result


def main():
    content=extract();oracle=UnlockOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_unlocks()
    examples=cases(content)
    for case in examples:
        try:
            rules=case.get('rules',content['rules']);oracle.load(case['state'],rules)
            for row in case['dependencies']:oracle.register(row)
            case['prepared']=oracle.snapshot()
            case['states']=[oracle.advance(step) for step in case['steps']]
            # Resume every transition from detached native storage too.
            current=case['prepared']
            for step,expected in zip(case['steps'],case['states']):
                oracle.load(current,rules);actual=oracle.advance(step)
                if actual!=expected:raise ValueError('Native restored continuation differs')
                current=actual['state']
        except Exception as error:raise ValueError('Original unlock '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    result=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],native_routines=content['native_routines'],
                adapters=[hex(a) for a in sorted(oracle.adapters)],cases=examples,scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_unlock_dispatch.json').write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Original unlock dispatch:',len(examples),'cases,',sum(len(c['steps']) for c in examples),'transitions')


if __name__=='__main__':main()
