"""Execute original temple affordability, start and full work-state block.

The work block enters its original parent frame at 0x10141204 and stops at
0x101414d8. Native powf and currency getters run. External hooks, spending,
type queries, notifications, completion visuals and follower action services
are in-memory adapters. Linked Ark follower traversal and reference clearing
execute. This does not execute the constructor, burial/destruction update,
reward redemption or the executable entrypoint.
"""
import copy
import json
import random
import struct

from tools.native_scenery_oracle import Oracle, ROOT
from tools.temple_repair import extract


def f32(value):return struct.unpack('<f',struct.pack('<f',value))[0]


def state(phase=5,**extra):
    return dict(handle=3,source_id=1012,phase=phase,food_cost=3,ore_cost=2,start_block=0,
                progress=0.,required=60.,reward='Card_Expansion',reward_pending=0,
                reward_ready=False,references=[41,42],notice_data=99,**extra)


class TempleOracle(Oracle):
    def configure_temple(self,rules):
        self.rules=rules
        self.configure(b'',b'',b'',[])
        self.adapters={0x10245d30:self.source_hook,0x10124660:self.spending,
                       0x10062d70:lambda:self.spend('spend_food'),0x10062b20:lambda:self.spend('spend_ore'),
                       0x1003ad80:lambda:self.kind('is_dock'),0x1003af80:lambda:self.kind('is_pit'),
                       0x100400b0:lambda:self.kind('is_settlement'),0x1003b1e0:lambda:self.kind('is_ark'),
                       0x102545c0:self.sound,0x1006b2e0:self.transition,0x10008860:self.start_action,
                       0x1003b840:self.reference_effect,0x10024700:self.context,0x100e0590:self.notice,
                       0x10140090:self.visual,0x1035fde0:self.format_unlock,
                       0x101b51e0:self.hash_string,0x101b5260:self.hash_value,0x1015cd60:self.unlock,
                       0x1035f830:lambda:self.return_integer()}
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        for address in [0x10062bb0,0x10062960,0x10141377]:
            self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe,begin=address,end=address))

    def event(self,name,args=()):self.events.append([name,list(args),self.integer(self.site+0x2fc)])
    def kind(self,name):self.event(name);self.return_integer(int(self.case.get(name,False)))
    def source_hook(self):
        name,identity=self.arguments(2)
        name=bytes(self.cpu.mem_read(name,80)).split(b'\0')[0].decode()
        self.event('hook',[name,identity])
        if name==self.rules['start_hook'] and 'hook_food_cost' in self.case:self.set_integer(self.site+0x408,self.case['hook_food_cost'])
        self.return_integer()
    def spending(self):self.event('spending_enabled');self.return_integer(int(self.case.get('spending_enabled',True)))
    def spend(self,name):self.event(name,[struct.unpack('<f',struct.pack('<I',self.arguments(1)[0]))[0]]);self.return_integer()
    def sound(self):self.event('sound',self.arguments(5));self.return_integer()
    def transition(self):
        pointer=self.cpu.reg_read(self.regs.UC_X86_REG_ECX)
        index=(pointer-self.GRIDS-0x20000)//0x13c
        action,target=self.arguments(2)
        self.event('transition',[self.case.get('followers',[])[index]['id'],action])
        self.return_integer(pop=8)
    def start_action(self):
        index=(self.arguments(1)[0]-self.GRIDS-0x20000)//0x13c
        self.event('start_action',[self.case.get('followers',[])[index]['id']]);self.return_integer()
    def reference_effect(self):
        player,value,flag=self.arguments(3)
        self.event('reference_effect',[player,struct.unpack('<f',struct.pack('<I',value))[0],flag])
        self.return_integer(pop=12)
    def context(self):self.event('notification_context');self.return_integer(self.SCRATCH+0x6000)
    def notice(self):
        context,kind,uid,payload=self.arguments(4)
        self.event('completion_notice',[context,kind,uid,self.integer(payload)]);self.return_integer()
    def visual(self):
        self.event('completion_visual')
        if self.case.get('clear_reward_during_visual',False):self.set_integer(self.site+0x234,0)
        self.return_integer()
    def format_unlock(self):
        target,format,identity=self.arguments(3)
        template=bytes(self.cpu.mem_read(format,80)).split(b'\0')[0].decode()
        if template!=self.rules['complete_unlock']:raise ValueError('Unexpected temple unlock format')
        identity=struct.unpack('<i',struct.pack('<I',identity))[0]
        result=(template%identity).encode()
        self.cpu.mem_write(target,result+b'\0')
        self.return_integer(len(result))
    def hash_string(self):
        pointer,=self.arguments(1)
        self.unlock_name=bytes(self.cpu.mem_read(pointer,80)).split(b'\0')[0].decode()
        self.return_integer(pop=4)
    def hash_value(self):self.return_integer(0x1234)
    def unlock(self):self.event('unlock',[self.unlock_name]);self.return_integer()
    def observe(self,cpu,address,size,user):
        if address==0x10141377:self.event('ark_followers')
        else:self.event('currency',['food' if address==0x10062bb0 else 'ore'])

    def load(self,case):
        self.case=case
        self.events=[]
        self.unlock_name=''
        current=case['state']
        self.site=self.POOL+current['handle']*0x43c
        self.cpu.mem_write(self.site,bytes(0x43c))
        self.set_integer(0x10f29ba0,self.POOL)
        self.set_integer(0x10f9e8ec,self.SCRATCH+0x7000)
        self.set_integer(self.SCRATCH+0x7000,self.POOL)
        for name,offset in [('phase',0x2fc),('source_id',0x10),('food_cost',0x408),('ore_cost',0x40c),('start_block',0x3c4),('reward_pending',0x238),('notice_data',0x130)]:self.set_integer(self.site+offset,current[name])
        for name,offset in [('progress',0x20),('required',0x3c8)]:self.set_float(self.site+offset,current[name])
        self.set_integer(self.site+0x234,123 if current['reward'] else 0)
        self.cpu.mem_write(self.site+0x2c0,bytes([int(current['reward_ready'])]))
        self.set_integer(self.site+4,self.SCRATCH+0x3000)
        self.set_integer(self.site+8,self.SCRATCH+0x3000+len(current['references'])*4)
        for index,value in enumerate(current['references']):self.set_integer(self.SCRATCH+0x3000+index*4,value)
        for name,address in [('food',0x1096c5e0),('ore',0x1096c628)]:self.cpu.mem_write(address,struct.pack('<q',int(case.get('currency',{}).get(name,10))))
        self.set_float(0x105d4c40,case.get('exponent',self.rules['exponent']))
        totals=case.get('totals',dict(workers=1,contributors=1,skill_sum=1.))
        index=current['handle']*4
        self.set_integer(0x10f9e8f0+index,totals['workers'])
        self.set_integer(0x10f9eb48+index,totals['contributors'])
        self.set_float(0x10f9eda0+index,totals['skill_sum'])
        self.set_integer(0x10d9b664,case.get('mode',0))
        self.set_integer(0x10d9b670,case.get('player',0))
        self.set_integer(self.SCRATCH+0x6000,12345)
        followers=case.get('followers',[])
        self.set_integer(0x10fcd450,self.GRIDS+0x20000)
        self.cpu.mem_write(0x10fcd45a,struct.pack('<H',0 if followers else 0xffff))
        for index,follower in enumerate(followers):
            pointer=self.GRIDS+0x20000+index*0x13c
            self.cpu.mem_write(pointer,bytes(0x13c))
            self.cpu.mem_write(pointer,struct.pack('<H',index+1 if index+1<len(followers) else 0xffff))
            target=self.GRIDS+0x30000+index*0x40
            self.set_integer(pointer+0x100,target)
            self.set_integer(target+0x20,self.site if follower.get('targets_site',False) else self.site+0x43c)

    def snapshot(self):
        result=copy.deepcopy(self.case['state'])
        for name,offset in [('phase',0x2fc),('reward_pending',0x238)]:result[name]=self.integer(self.site+offset)
        for name,offset in [('food_cost',0x408),('ore_cost',0x40c)]:result[name]=struct.unpack('<i',self.cpu.mem_read(self.site+offset,4))[0]
        result['reward']=result['reward'] if self.integer(self.site+0x234) else 0
        result['reward_ready']=bool(self.cpu.mem_read(self.site+0x2c0,1)[0])
        result['progress']=self.float(self.site+0x20)
        size=(self.integer(self.site+8)-self.integer(self.site+4))//4
        result['references']=result['references'][:size]
        return result

    def run_case(self,case):
        self.load(case)
        action=case['action']
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.site)
        if action=='can_pay':value=bool(self.call(0x1013ced0)&255)
        elif action=='currency_allowed':value=bool(self.call(0x1013ce70,[case['kind']])&255)
        elif action=='begin':
            self.call(0x1013d8b0)
            value=any(event[0]=='hook' for event in self.events)
        else:
            frame=self.STACK+0x80000
            self.set_float(frame+8,case.get('delta',.1))
            self.cpu.reg_write(self.regs.UC_X86_REG_ESP,frame-0x200)
            self.cpu.reg_write(self.regs.UC_X86_REG_EBP,frame)
            self.cpu.reg_write(self.regs.UC_X86_REG_ESI,self.site)
            self.cpu.reg_write(self.regs.UC_X86_REG_EBX,0)
            self.cpu.reg_write(self.regs.UC_X86_REG_EDI,0)
            self.cpu.mem_write(self.SCRATCH+0x700,b'\xdb\xe3')
            self.cpu.emu_start(self.SCRATCH+0x700,self.SCRATCH+0x702)
            self.cpu.emu_start(0x10141204,0x101414d8,count=500000)
            if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=0x101414d8:raise ValueError('Temple work budget exhausted')
            value=any(event[0]=='hook' and event[1][0]==self.rules['complete_hook'] for event in self.events)
        return dict(value=value,state=self.snapshot(),events=self.events)


def cases():
    cases=[]
    for phase in range(9):
        for food,ore in [(0,0),(3,2),(2,3),(0x100000000,0x100000000),(-1,-1),(0x7fffffffffffffff,0x7fffffffffffffff)]:
            cases.append(dict(name=f'pay_{phase}_{food}_{ore}',action='can_pay',state=state(phase),currency=dict(food=food,ore=ore)))
        for kind in range(4):cases.append(dict(name=f'currency_{phase}_{kind}',action='currency_allowed',state=state(phase),kind=kind,currency=dict(food=2,ore=1)))
        for blocked in [0,1]:
            for spend in [False,True]:cases.append(dict(name=f'begin_{phase}_{blocked}_{spend}',action='begin',state=dict(state(phase),start_block=blocked),spending_enabled=spend))
    for name,changes in [('zero',dict(food_cost=0,ore_cost=0)),('signed',dict(food_cost=-1,ore_cost=-2)),('float_round',dict(food_cost=2147483647,ore_cost=16777217))]:
        cases.append(dict(name='begin_'+name,action='begin',state=dict(state(),**changes)))
    cases.append(dict(name='begin_hook_updates_cost',action='begin',state=state(),hook_food_cost=7))
    for phase in range(9):cases.append(dict(name='work_phase_'+str(phase),action='work',state=dict(state(phase),required=.1)))
    base=dict(action='work',state=dict(state(6),required=1.,progress=.9),delta=.1,totals=dict(workers=1,contributors=1,skill_sum=1.))
    for name,options in [('exact',{}),('under',dict(delta=.099)),('over',dict(delta=.101)),
                         ('dock',dict(is_dock=True)),('pit',dict(is_pit=True)),('settlement',dict(is_settlement=True)),
                         ('ark',dict(is_ark=True,followers=[dict(id=11,targets_site=True),dict(id=12,targets_site=False),dict(id=13,targets_site=True)])),
                         ('mode1',dict(mode=1)),('mode2',dict(mode=2)),('player_max',dict(player=0xffffffff)),
                         ('no_reward',dict(state=dict(state(6),required=.1,reward=0))),
                         ('no_reward_mode1',dict(mode=1,state=dict(state(6),required=.1,reward=0))),
                         ('visual_clears_reward',dict(clear_reward_during_visual=True)),
                         ('no_references',dict(state=dict(state(6),required=.1,references=[]))),
                         ('already_full_no_workers',dict(state=dict(state(6),progress=1.,required=1.),totals=dict(workers=0,contributors=0,skill_sum=0.))),
                         ('no_workers',dict(totals=dict(workers=0,contributors=1,skill_sum=1.))),
                         ('no_contributors',dict(totals=dict(workers=1,contributors=0,skill_sum=1.)))]:
        case=copy.deepcopy(base);case.update(name='work_'+name,**copy.deepcopy(options));cases.append(case)
    rng=random.Random(0x10141204)
    for index in range(80):
        count=rng.choice([0,1,2,3,8,30,300,0xffffffff])
        contributors=rng.choice([0,1,2,3,8,30,300,0xffffffff])
        cases.append(dict(name='arithmetic_'+str(index),action='work',state=dict(state(6),progress=f32(rng.random()*5),required=1000.),
                          totals=dict(workers=count,contributors=contributors,skill_sum=f32(rng.random()*100)),
                          exponent=rng.choice([0.,.35,.8,1.]),delta=f32(rng.random())))
    for case in cases:
        for name in ['progress','required']:case['state'][name]=f32(case['state'][name])
    return cases


def main():
    content=extract()
    oracle=TempleOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_temple(content['rules'])
    examples=cases()
    for case in examples:
        try:case['expected']=oracle.run_case(case)
        except Exception as error:raise ValueError('Original temple case '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
        for name,value in case.get('currency',{}).items():
            if abs(value)>9007199254740991:case['currency'][name]=str(value)
    sequences=[]
    for exponent in [content['rules']['exponent'],1.]:
        initial=dict(state(6),progress=0.,required=1000.)
        sequence=dict(exponent=exponent,initial=copy.deepcopy(initial),states=[])
        for _ in range(10):
            case=dict(action='work',state=initial,exponent=exponent,delta=.1,totals=dict(workers=2,contributors=2,skill_sum=2.))
            result=oracle.run_case(case)
            sequence['states'].append(result)
            initial=result['state']
        sequences.append(sequence)
    result=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],cases=examples,sequences=sequences,native_routines=content['native_routines'],
                adapters=[hex(a) for a in sorted(oracle.adapters)],observation_hooks=['0x10062bb0','0x10062960','0x10141377'],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_temple_repair.json').write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Original temple repair:',len(examples),'cases',flush=True)


if __name__=='__main__':main()
