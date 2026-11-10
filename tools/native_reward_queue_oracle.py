"""Execute complete original reward admission, collection and LIFO consumption.

Actual lookup/type/limit/acquire/spend/gem/totem/seed helpers execute. Only map
and vector storage, diagnostics, explicit RNG, mission context, current-currency
helpers, research services and special unit/name effects are adapters. No game
entrypoint, device, OS, GUI or wall clock executes.
"""
import copy
import json
import random
import struct

from tools.native_availability_oracle import AvailabilityStorage,empty as empty_availability
from tools.native_reward_dispatch_oracle import DispatchOracle,empty,pack
from tools.native_scenery_oracle import ROOT
from tools.reward_dispatch import extract as dispatch_content,key
from tools.reward_queue import extract


def f32(value):return struct.unpack('<f',struct.pack('<f',value))[0]
def initial():return dict(queue=[],delay=1.,gems=0,deferred={name:[0,0] for name in ['belief','wheat','ore']},totem_capacity=[0]*8,win_name='')
def entry(reward=50,kind=0,flags=2,reason=8,source_id=1012,taken=None,display=None):
    return dict(reward=reward,kind=kind,flags=flags,reason=reason,source_id=source_id,
                taken=bool(flags&2) if taken is None else taken,display=not bool(flags&16) if display is None else display)
def card(identity=50,type=2,research_needed=1,category=1):return dict(id=identity,type=type,research_needed=research_needed,category=category,silent=0)
def records():return dict(cards=[card()],stickers=[dict(id=60),dict(id=key('Sticker_Gem_1'))],special=[])
def special(identity=50,**extra):return dict(id=identity,gems=0,belief=0,wheat=0,ore=0,followers=0,role=0,extra=0,**extra)


class QueueOracle(DispatchOracle):
    OWNER=0x10f18cd0

    def configure_queue(self,content):
        self.queue_content=content
        self.configure_dispatch(dispatch_content())
        for address in [0x10050170,0x100015b0]:del self.adapters[address]
        self.adapters.update({0x10001360:lambda:self.storage.lookup(),0x10179af0:self.log,
                              0x1035fde0:self.format,0x1035f830:lambda:self.return_integer(self.cpu.reg_read(self.regs.UC_X86_REG_EAX)),
                              0x10062f90:lambda:self.currency('belief'),0x10062a90:lambda:self.currency('wheat'),0x10062ce0:lambda:self.currency('ore'),
                              0x101343b0:lambda:self.void('revive_explorers'),0x1019a960:lambda:self.void('changed'),
                              0x10024700:lambda:self.void('context',self.SCRATCH+0x6000),
                              0x1015cc90:lambda:self.with_arg('acquired'),0x10027330:self.remaining,
                              0x100273d0:self.complete,0x10027410:self.finish,
                              0x10028420:self.credit,0x1002c670:self.mission_spawn,
                              0x100f3e30:self.spawn,0x10050740:self.win_name,
                              0x1012fef0:self.mission_type,0x1004fbb0:self.vector_append,0x10245d30:self.source_hook})
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        for address in [0x100242f0,0x1019a910,0x10026880]:
            self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_queue,begin=address,end=address))
        self.set_integer(0x107ded34,content['rules']['gem_sticker'])
        for i,value in enumerate(content['rules']['actions']):self.set_integer(0x107dee84+i*4,value)

    def length(self):return (self.integer(self.OWNER+4)-self.integer(self.OWNER))//24
    def event(self,name,args=()):self.events.append([name,list(args),self.length()])
    def void(self,name,value=0):self.event(name);self.return_integer(value)
    def with_arg(self,name):self.event(name,self.arguments(1));self.return_integer()
    def refresh(self):self.void('refresh')
    def source_hook(self):
        text,identity=self.arguments(2)
        text=bytes(self.cpu.mem_read(text,100)).split(b'\0')[0].decode()
        self.event('hook',[text,identity])
        self.return_integer()
    def word(self):
        words=self.case.get('words',[0])
        result=words[self.random_calls%len(words)]
        self.random_calls+=1
        self.return_integer(result)

    def observe_queue(self,cpu,address,size,user):
        if address==0x1019a910:self.event('totem_upgrade',self.arguments(1))
        elif address==0x10026880:self.event('card_acquired',[self.current_card()])
        else:
            amount,reason,text,source,flag=self.arguments(5)
            amount=struct.unpack('<i',struct.pack('<I',amount))[0]
            text=bytes(self.cpu.mem_read(text,200)).split(b'\0')[0].decode()
            self.event('gem_credit',[amount,reason,text,source,flag])

    def log(self):
        channel,format=self.arguments(2)
        if channel==35:self.storage.diagnostic();return
        text=bytes(self.cpu.mem_read(format,200)).split(b'\0')[0].decode()
        args=[]
        if '%i' in text or '%u' in text:
            value=self.arguments(3)[2]
            args=[struct.unpack('<i',struct.pack('<I',value))[0] if '%i' in text else value]
        self.event('log',[channel,text,args])
        self.return_integer()

    def format(self):
        target,format,value=self.arguments(3)
        text=bytes(self.cpu.mem_read(format,200)).split(b'\0')[0].decode()
        if '%i' not in text:raise ValueError('Unexpected queue text format')
        value=struct.unpack('<i',struct.pack('<I',value))[0]
        text=text%value
        self.cpu.mem_write(target,text.encode()+b'\0')
        self.return_integer(len(text))

    def currency(self,name):
        value=self.arguments(1)[0]
        if name=='belief' and self.arguments(2)[1]!=2:raise ValueError('Unexpected belief reason')
        self.event('currency',[name,struct.unpack('<f',struct.pack('<I',value))[0]])
        self.return_integer(1)

    def current_card(self):return self.integer(self.cpu.reg_read(self.regs.UC_X86_REG_ECX))
    def profile(self,name,default=None):return self.step.get(name,self.case.get(name,default))
    def remaining(self):
        identity=self.current_card()
        self.event('research_remaining',[identity])
        self.return_integer(max(0,self.profile('research_remaining',0)-self.research.get(str(identity),0)))
    def complete(self):
        identity=self.current_card()
        self.event('research_complete',[identity])
        self.return_integer(int(self.profile('research_complete',False)))
    def finish(self):self.event('complete_card',[self.current_card()]);self.return_integer()
    def credit(self):
        identity=self.current_card()
        sticker,count=self.arguments(2)
        self.event('research_credit',[identity,sticker,count])
        self.research[str(identity)]=self.research.get(str(identity),0)+count
        self.return_integer(pop=8)
    def mission_type(self):self.event('mission_type');self.return_integer(self.profile('mission_type',1))

    def mission_spawn(self):
        self.event('mission_spawn')
        position=self.profile('spawn_position',[3.,4.,5.])
        extra=self.profile('spawn_extra',[0.,0.,0.])
        for i,value in enumerate(position):self.set_float(self.SCRATCH+0x7000+0x14c+i*4,value)
        for i,value in enumerate(extra):self.set_float(0x11165d10+i*4,value)
        self.return_integer(self.SCRATCH+0x7000)
    def spawn(self):
        args=self.arguments(11)
        position=list(struct.unpack('<3f',struct.pack('<3I',*args[:3])))
        extra=list(struct.unpack('<3f',struct.pack('<3I',*args[8:])))
        count=struct.unpack('<i',struct.pack('<I',args[5]))[0]
        self.event('spawn_followers',[position,args[3],args[4],count,args[6],args[7],extra])
        self.return_integer()
    def win_name(self):
        output,text=self.arguments(2)
        text=bytes(self.cpu.mem_read(text,1025)).split(b'\0')[0].decode()
        self.event('win_name',[text])
        self.set_integer(output,123)
        self.return_integer(output,pop=8)

    def vector_append(self):
        position,source,_,count,flag=self.arguments(5)
        if count!=1 or flag!=1:raise ValueError('Unexpected reward vector insertion')
        owner=self.cpu.reg_read(self.regs.UC_X86_REG_ECX)
        target=self.integer(owner+4)
        self.cpu.mem_write(target,bytes(self.cpu.mem_read(source,24)))
        self.set_integer(owner+4,target+24)
        self.set_integer(owner+8,target+24+128*24)
        self.return_integer(pop=20)

    def store_entry(self,pointer,value):
        for i,field in enumerate(['kind','reason','source_id','reward','flags']):self.set_integer(pointer+4*i,value[field])
        self.cpu.mem_write(pointer+20,bytes([int(value['taken']),int(value['display']),0,0]))
    def read_entry(self,pointer):
        result={field:self.integer(pointer+4*i) for i,field in enumerate(['kind','reason','source_id','reward','flags'])}
        result.update(taken=bool(self.cpu.mem_read(pointer+20,1)[0]),display=bool(self.cpu.mem_read(pointer+21,1)[0]))
        return result

    def load_queue(self,case):
        compatible=dict(case,state=case.get('dispatch_state',dict(stories_acquired=[],pack_count=case.get('pack_count',0),pack_index=case.get('pack_index',0))),
                        records=dict(empty(),cards=[dict(row,silent=row.get('silent',0)) for row in case['records']['cards']],stickers=case['records']['stickers'],
                                     packs=case['records'].get('packs',[]),stories=case['records'].get('stories',[])))
        self.load(compatible)
        self.case=case
        self.step={}
        self.events=[]
        self.random_calls=0
        self.research={}
        self.storage=AvailabilityStorage(self,case.get('availability',empty_availability()),base=self.GRIDS+0x100000)
        self.set_integer(0x10d9b664,case.get('mode',0))
        self.set_integer(0x10d9b670,case.get('player',0))
        self.cpu.mem_write(0x10fbdfe8,bytes(50*8))
        for i,identity in enumerate(self.queue_content['rules']['exempt']):self.set_integer(0x10fbdfe8+i*8,identity)
        self.cpu.mem_write(0x10f13b30,bytes(256*32))
        for i,row in enumerate(case['records']['special']):
            for j,field in enumerate(['id','gems','belief','wheat','ore','followers','role','extra']):self.set_integer(0x10f13b30+i*32+j*4,row[field])
        for i,row in enumerate(case['records']['cards']):
            self.set_integer(0x10f0b30c+i*0x38+0x1c,row['research_needed'])
            self.set_integer(0x10f0b30c+i*0x38+0x18,row['category'])
        current=case.get('state',initial())
        self.begin=self.POOL+0x1800000
        self.set_integer(self.OWNER,self.begin)
        self.set_integer(self.OWNER+4,self.begin+len(current['queue'])*24)
        self.set_integer(self.OWNER+8,self.begin+case.get('capacity',len(current['queue'])+128)*24)
        for i,value in enumerate(current['queue']):self.store_entry(self.begin+i*24,value)
        self.set_float(self.OWNER+0x18,current['delay'])
        self.set_integer(0x1057a80c,current['gems'])
        for field,address in [('belief',0x110344d0),('wheat',0x110344e0),('ore',0x110344f0)]:
            for i,word in enumerate(current['deferred'][field]):self.set_integer(address+i*4,word)
        for i,value in enumerate(current['totem_capacity']):self.set_integer(0x10d9b830+i*4,value)
        self.cpu.mem_write(0x10fcd510,current['win_name'].encode()+b'\0')
        self.set_integer(0x1108e998,self.POOL+0x1d00000)
        for name,address in [('auto_claim',0x105a1534),('delay',0x105a158c),('totem_upgrade',0x105e30fc)]:self.set_float(address,case.get(name,self.queue_content['rules'][name]))

    def snapshot_queue(self):
        return dict(queue=[self.read_entry(self.begin+i*24) for i in range(self.length())],delay=self.float(self.OWNER+0x18),gems=self.integer(0x1057a80c),
                    deferred={field:[self.integer(address),self.integer(address+4)] for field,address in [('belief',0x110344d0),('wheat',0x110344e0),('ore',0x110344f0)]},
                    totem_capacity=[self.integer(0x10d9b830+i*4) for i in range(8)],win_name=bytes(self.cpu.mem_read(0x10fcd510,1025)).split(b'\0')[0].decode())

    def advance(self,step):
        self.step=step
        self.events=[]
        self.storage.events=[]
        self.set_integer(0x10d9b664,self.profile('mode',0))
        self.set_integer(0x10d9b670,self.profile('player',0))
        self.set_float(self.POOL+0x1d00000+0x7b600,self.profile('population',100.))
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.OWNER)
        action=step['action']
        if action=='admit':
            args=[step.get(field,default) for field,default in [('reward',50),('kind',0),('flags',2),('reason',8),('source_id',1012)]]
            value=bool(self.call(0x10050170,args,limit=1000000)&255)
        elif action=='consume':
            previous=self.length();self.call(0x10051080,limit=1000000);value=self.length()<previous
        elif action=='take':
            self.call(0x1004eee0,[self.SCRATCH+0x3000,step.get('kind',0),step.get('reason',12)],limit=1000000)
            value=self.read_entry(self.SCRATCH+0x3000)
        elif action=='select':
            result=self.call(0x1004eda0,[step.get('kind',0),step.get('reason',12)],limit=1000000)
            value=(result-self.begin)//24 if result else -1
        elif action in ['dispatch','chest','temple']:
            args=[step.get('reward',50),step.get('source_id',1012),step.get('flags',0)]
            if action=='dispatch':self.call(0x10050930,[*args,step.get('reason',8),step.get('override',0)],limit=2000000)
            else:self.call(0x100514f0 if action=='chest' else 0x10051520,args,limit=2000000)
            value=True
        else:
            routine={'can_acquire':0x10001670,'acquire':0x100016e0,'spend':0x10001800}[action]
            value=bool(self.call(routine,[step['reward'],step['count']],limit=1000000)&255)
        return dict(value=value,state=self.snapshot_queue(),dispatch=self.snapshot(),availability=self.storage.snapshot(),availability_events=copy.deepcopy(self.storage.events),events=self.events,random_calls=self.random_calls,research=copy.deepcopy(self.research))


def cases(content):
    examples=[]
    for mode in [0,1,2,3,7]:
        for kind in [0,1,2]:
            for reward in [0,50,60,999]:
                examples.append(dict(name=f'admit_{mode}_{kind}_{reward}',mode=mode,records=records(),steps=[dict(action='admit',reward=reward,kind=kind),dict(action='consume')]))
    for flags in range(32):
        examples.append(dict(name=f'flags_{flags}',records=records(),steps=[dict(action='admit',flags=flags),dict(action='take'),dict(action='consume'),dict(action='consume')]))
    for needed in [-1,0,1,10]:
        for type in [1,2,3]:
            examples.append(dict(name=f'card_{type}_{needed}',records=dict(records(),cards=[card(type=type,research_needed=needed)]),research_remaining=3,research_complete=True,
                                 steps=[dict(action='admit',flags=0),dict(action='take'),dict(action='consume'),dict(action='consume')]))
    for mode in [0,1,2,3]:
        for flags in [0,2,4,8,12]:
            row=dict(special(),gems=3,belief=16777217,wheat=10,ore=20)
            examples.append(dict(name=f'special_{mode}_{flags}',mode=mode,records=dict(records(),special=[row]),
                                 steps=[dict(action='admit',flags=flags),dict(action='take'),dict(action='consume')]))
    for pack_count in [0,1,5,-1]:
        for pack_index in [0,1]:
            for reason in [7,8]:
                for source in [0,1012]:
                    examples.append(dict(name=f'gem_{pack_count}_{pack_index}_{reason}_{source}',records=records(),pack_count=pack_count,pack_index=pack_index,
                                         steps=[dict(action='admit',reward=content['rules']['gem_sticker'],kind=1,flags=2,reason=reason,source_id=source),dict(action='consume')]))
    for name,available in [('stock',dict(stock_registered={'@50':True},stock_limits={'@50':1})),('lifetime',dict(acquisition_registered={'@50':True},acquisition_limits={'@50':1})),
                           ('full',dict(stock_registered={'@50':True},stock_limits={'@50':1},acquired={'@50':1})),
                           ('underflow',dict(stock_registered={'@50':True},stock_limits={'@50':2},spent={'@50':1}))]:
        limits=empty_availability();limits.update(available)
        examples.append(dict(name='capacity_'+name,records=records(),availability=limits,steps=[dict(action='admit'),dict(action='admit'),dict(action='consume'),dict(action='admit')]))
    for extra in content['rules']['actions']:
        for word in [0,16383,16384,32767]:
            row=dict(special(),followers=2,role=9,extra=extra)
            current=initial();current['win_name']='Original tribe';current['totem_capacity'][3]=0xffffffff
            examples.append(dict(name=f'extra_{extra}_{word}',records=dict(records(),special=[row]),state=current,player=3,words=[word],
                                 steps=[dict(action='admit'),dict(action='consume'),dict(action='consume')]))
    for mode in [0,1,2,3]:
        for mission in [0,1]:
            for reason in [2,4,8,12]:
                current=initial();current['queue']=[entry(taken=False,flags=0,reason=r,source_id=100) for r in [4,2,8]]
                examples.append(dict(name=f'take_{mode}_{mission}_{reason}',mode=mode,mission_type=mission,records=records(),state=current,
                                     steps=[dict(action='select',reason=reason),dict(action='take',reason=reason),dict(action='consume')]))
    for auto in [0,1]:
        for delay in [0.,.5,1.,1.5]:
            current=initial();current['delay']=delay;current['queue']=[entry(taken=False,flags=0,reason=8) for _ in range(3)]
            examples.append(dict(name=f'fast_{auto}_{delay}',records=records(),state=current,auto_claim=auto,
                                 steps=[dict(action='take'),dict(action='consume'),dict(action='consume'),dict(action='consume')]))
    for case_name,alter in [('vector_growth',dict(capacity=0)),('zero_research_capacity',dict(availability=dict(empty_availability(),stock_registered={'@50':True},stock_limits={'@50':0})) )]:
        examples.append(dict(name=case_name,records=records(),steps=[dict(action='admit'),dict(action='consume')],**alter))
    for row in content['special']:
        registered=dict(records(),cards=[card(row['id'],type=1)],special=[row])
        examples.append(dict(name='source_'+row['name'],records=registered,steps=[dict(action='admit',reward=row['id']),dict(action='consume')]))
    for action in ['can_acquire','acquire','spend']:
        for count in [0,1,2,0xffffffff]:
            for acquired,spent in [(0,0),(1,0),(0xffffffff,0),(0,1)]:
                limits=dict(empty_availability(),stock_registered={'@50':True},acquisition_registered={'@50':True},stock_limits={'@50':3},acquisition_limits={'@50':4},acquired={'@50':acquired},spent={'@50':spent})
                examples.append(dict(name=f'{action}_{count}_{acquired}_{spent}',records=records(),availability=limits,steps=[dict(action=action,reward=50,count=count)]))
    for identity in content['rules']['exempt']:
        examples.append(dict(name='exempt_'+str(identity),records=records(),steps=[dict(action='acquire',reward=identity,count=0xffffffff),dict(action='spend',reward=identity,count=0xffffffff)]))
    for kind in [0,1,2]:
        available=dict(empty_availability(),acquired={'@50':3},spent={'@50':0})
        examples.append(dict(name='double_spend_'+str(kind),records=dict(records(),stickers=[dict(id=50)]),availability=available,
                             steps=[dict(action='admit',reward=50,kind=kind,flags=6),dict(action='consume')]))
    current=initial();current['deferred']={'belief':[0xffffffff,0x7fffffff],'wheat':[0,0x80000000],'ore':[0xffffffff,0xffffffff]};current['gems']=0xffffffff
    examples.append(dict(name='signed_resource_carry',mode=7,records=dict(records(),special=[dict(special(),belief=1,wheat=-1,ore=2,gems=2)]),state=current,steps=[dict(action='admit')]))
    examples.append(dict(name='fractional_totem',records=dict(records(),special=[dict(special(),extra=content['rules']['actions'][1])]),totem_upgrade=1.75,steps=[dict(action='admit'),dict(action='consume')]))
    # Dispatcher + original admission + original actual inventory consumption.
    # Selection remains an explicit service; it returns the controlled sticker 60.
    shared=dispatch_content()
    for row in shared['tables']['initialworldsetup/packdata.csv'][1:]:
        if not row or not row[0].startswith('Pack_'):continue
        slots=[(int(row[4+2*i] or 0),key(row[5+2*i])) for i in range(5)]
        count=sum(max(0,c) for c,_ in slots)
        configured=dict(records(),packs=[pack(key(row[0]),slots)])
        steps=[dict(action='temple',reward=key(row[0]))]
        steps.extend(dict(action='take',kind=1) for _ in range(count))
        steps.extend(dict(action='consume') for _ in range(count+1))
        examples.append(dict(name='pipeline_'+row[0],records=configured,selected_sticker=60,steps=steps))
    for reason in [7,8]:
        configured=dict(records(),cards=[dict(card(),silent=1)])
        examples.append(dict(name='pipeline_silent_'+str(reason),records=configured,
                             steps=[dict(action='dispatch',reward=50,reason=reason),dict(action='take'),dict(action='consume'),dict(action='dispatch',reward=50,reason=reason),dict(action='consume')]))
    return examples


def main():
    content=extract()
    oracle=QueueOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_queue(content)
    examples=cases(content)
    for case in examples:
        try:
            oracle.load_queue(case)
            case['states']=[oracle.advance(step) for step in case['steps']]
        except Exception as error:raise ValueError('Original queue case '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    result=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],cases=examples,
                native_routines=dict(content['native_routines'],**{name:code for name,code in dispatch_content()['native_routines'].items() if name in ['0x10050930','0x100514f0','0x101b51e0','0x101b5260']}),
                adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_reward_queue.json').write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Original reward queue:',len(examples),'cases,',sum(len(case['steps']) for case in examples),'transitions',flush=True)


if __name__=='__main__':main()
