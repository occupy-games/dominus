"""Execute original chest exposure, opening and the complete lifetime pool loop.

Ground/sculpt storage, influence, renderer/audio intents, progression/reward
services and pool/spatial storage are explicit adapters. The original timers,
height response, phase transitions, reward gates/order, destructor ID write and
whole-pool traversal/totals execute. Reward redemption and the full input/picking
controller are outside this comparison. No original OS/device/entrypoint runs.
"""
import argparse
import copy
import json
import struct

from tools.native_scenery_oracle import Oracle, ROOT
from tools.native_storm_chests_oracle import word
from tools.storm_chests import extract


def f32(value):return struct.unpack('<f',struct.pack('<f',value))[0]


def chest(handle=0,phase=0,elapsed=0.,height=6.,base=6.,x=160.,z=120.,kind=0,source_id=0,reward='Reward_RandomStickerOrGem',uid_low=0,uid_high=0):
    # Explicit controlled numeric records, independently checked by the original
    # constructor comparison; no geometry/reward rules are implemented here.
    position=[f32(x),f32(z),f32(height)]
    slots={'1c':0.,'58':f32(elapsed),'60':phase,'6c':0,'70':0,'98':True,'9c':8.,'a0':uid_low,'a4':uid_high}
    core=dict(kind=kind,position=position,base_height=f32(base),rotation=180.,source_slots=slots,
              spatial=dict(kind=5,position=position[:2],radius=1.,flag=1),registered=0<=int(x)<=1024 and 0<=int(z)<=1024)
    return dict(handle=handle,source_id=source_id,reward=reward,core=core)


class LifetimeOracle(Oracle):
    def configure_lifetime(self):
        self.adapters={0x1025c150:self.ground,0x10144cd0:self.sculpt,0x10257570:self.influence,
                       0x10335ee9:self.animation,0x10335051:lambda:self.return_integer(),
                       0x1024d580:self.open_notification,0x1002c670:self.mission_mode,0x10130f30:self.mission_score,
                       0x10179af0:self.opened_log,0x10001600:self.reward_available,0x1012ff20:self.reward_status,
                       0x100514f0:self.grant,0x1015c1e0:self.unlocked,0x1015c240:self.unlock,
                       0x1004cc30:lambda:self.query_bool('reward_type_a'),0x1004fe70:lambda:self.query_bool('reward_type_b'),
                       0x101344d0:self.finish_target,0x100eb200:lambda:self.query_bool('mode2_ready'),
                       0x100ebfa0:lambda:self.query_bool('mode2_available'),0x10024700:lambda:self.query_void('mode2_prepare'),
                       0x100f1ba0:self.unregister,0x1007b6a0:self.release,0x1035fde0:self.format_diagnostic}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.handles.extend([self.cpu.hook_add(self.hook_kind,self.destroy,begin=0x101521b0,end=0x101521b0),
                             self.cpu.hook_add(self.hook_kind,self.increment,begin=0x10152ae4,end=0x10152ae4)])

    def handle(self):return (self.cpu.reg_read(self.regs.UC_X86_REG_ESI)-self.POOL)//0xa8
    def event(self,name,args=(),handle=None):self.events.append([name,self.handle() if handle is None else handle,list(args)])
    def profile(self,key,default=None):return self.step.get(key,self.case.get(key,default))
    def key(self,value):return self.names.get(value,value)
    def token(self,value):
        if isinstance(value,int):return value
        if value not in self.tokens:
            number=1000+len(self.tokens)
            self.tokens[value]=number
            self.names[number]=value
        return self.tokens[value]

    def ground(self):
        x,z,flag=self.arguments(3)
        if flag:raise ValueError('Unexpected ground flag')
        self.event('ground',struct.unpack('<2f',struct.pack('<2I',x,z)))
        self.return_float(self.profile('ground',6.))

    def sculpt(self):
        x,z,out=self.arguments(3)
        self.event('sculpt',struct.unpack('<2i',struct.pack('<2I',x,z)))
        self.set_float(out,self.profile('sculpt_height',20.))
        self.return_integer(int(self.profile('sculpt_active',False)))

    def influence(self):
        x,z,flag=self.arguments(3)
        self.event('influence',[*struct.unpack('<2i',struct.pack('<2I',x,z)),bool(flag)])
        self.return_integer(int(self.profile('influence',True)))

    def animation(self):self.event('animation',[10]);self.return_integer(pop=16)
    def open_notification(self):
        _,pointer,flag=self.arguments(3)
        if flag:raise ValueError('Unexpected notification flag')
        self.event('open_notification',struct.unpack('<3f',self.cpu.mem_read(pointer,12)))
        self.return_integer()

    def increment(self,cpu,address,size,user):self.event('increment_opened')
    def mission_mode(self):
        self.event('mission_mode')
        self.set_integer(self.SCRATCH+0x6000+0x258,self.profile('mission_mode',0))
        self.return_integer(self.SCRATCH+0x6000)
    def mission_score(self):
        score,*position=self.arguments(5)
        self.event('mission_score',[score,list(struct.unpack('<4f',struct.pack('<4I',*position)))])
        self.return_integer()

    def opened_log(self):
        channel,format,key,phase=self.arguments(4)
        if channel!=10 or phase!=2:raise ValueError('Unexpected chest log')
        self.event('opened_log',[key,phase])
        self.return_integer()
    def reward_available(self):
        key,=self.arguments(1)
        self.event('reward_available',[self.key(key)])
        self.return_integer(self.SCRATCH+0x7000 if self.profile('reward_available',True) else 0)
    def reward_status(self):
        self.event('reward_status')
        values=self.profile('reward_status',False)
        value=values[min(self.status_calls,len(values)-1)] if isinstance(values,list) else values
        self.status_calls+=1
        self.return_integer(int(value))
    def grant(self):
        reward,key,flags=self.arguments(3)
        self.event('grant',[self.key(reward),key,flags])
        if self.profile('unlock_during_grant',False):self.unlocks.add('CHEST_BONUS_1')
        self.return_integer(pop=12)
    def unlocked(self):
        pointer,=self.arguments(1)
        name=bytes(self.cpu.mem_read(pointer,80)).split(b'\0')[0].decode()
        self.event('unlocked',[name])
        self.return_integer(int(name in self.unlocks))
    def unlock(self):
        pointer,=self.arguments(1)
        name=bytes(self.cpu.mem_read(pointer,80)).split(b'\0')[0].decode()
        self.event('unlock',[name])
        self.unlocks.add(name)
        self.return_integer()
    def query_bool(self,name):
        args=[self.key(self.arguments(1)[0])] if name.startswith('reward_type') else []
        self.event(name,args)
        self.return_integer(int(self.profile(name,False)))
    def query_void(self,name):self.event(name);self.return_integer()
    def finish_target(self):
        key,=self.arguments(1)
        self.event('finish_target',[key])
        self.return_integer()

    def format_diagnostic(self):
        target,format,index=self.arguments(3)
        template=bytes(self.cpu.mem_read(format,80)).split(b'\0')[0].decode()
        if template!='StickersToGet_%i' or index>3:raise ValueError('Unexpected chest diagnostic format')
        result=(template%index).encode()
        self.cpu.mem_write(target,result+b'\0')
        self.return_integer(len(result))

    def destroy(self,cpu,address,size,user):
        pointer=cpu.reg_read(self.regs.UC_X86_REG_ECX)
        self.event('destroy',handle=(pointer-self.POOL)//0xa8)
    def unregister(self):
        pointer=self.cpu.reg_read(self.regs.UC_X86_REG_ECX)
        handle=(pointer-self.POOL-0x78)//0xa8
        item=self.original[handle]
        self.event('unregister',[item['core']['spatial']],handle)
        self.set_integer(pointer+4,0)
        self.return_integer()
    def release(self):
        pointer,=self.arguments(1)
        handle=(pointer-self.POOL)//0xa8
        next=self.integer(pointer)&0xffff
        index=self.active.index(handle)
        if index:self.cpu.mem_write(self.POOL+self.active[index-1]*0xa8,struct.pack('<H',next))
        else:self.cpu.mem_write(0x10fcd496,struct.pack('<H',next))
        self.active.remove(handle)
        self.removed.append(handle)
        self.event('release',handle=handle)
        self.return_integer(self.POOL+next*0xa8 if next!=0xffff else 0,pop=4)

    def load(self,case,rules):
        self.case=case
        self.step={}
        self.tokens={}
        self.names={}
        self.active=[c['handle'] for c in case['chests']]
        self.original={c['handle']:copy.deepcopy(c) for c in case['chests']}
        self.unlocks=set(case.get('unlocks',[]))
        self.set_integer(0x10fcd48c,self.POOL)
        self.set_integer(0x10fcd496,self.active[0] if self.active else 0xffff)
        self.set_integer(0x10bb2a0c,0)
        self.set_integer(0x10f27f94,0)
        self.set_integer(0x10f19edc,self.SCRATCH+0x5000)
        self.set_integer(0x10f19ee0,self.SCRATCH+0x5000+case.get('authored_words',0)*4)
        for index,item in enumerate(case['chests']):
            pointer=self.POOL+item['handle']*0xa8
            self.cpu.mem_write(pointer,bytes(0xa8))
            self.set_integer(pointer,self.active[index+1] if index+1<len(self.active) else 0xffff)
            self.set_integer(pointer+4,item['source_id'])
            core=item['core']
            for i,value in enumerate(core['position']):self.set_float(pointer+0x44+i*4,value)
            for key,offset in [('kind',0x50),('rotation',0x64),('base_height',0x5c)]:
                (self.set_integer if key=='kind' else self.set_float)(pointer+offset,core[key])
            for key,value in core['source_slots'].items():
                address=pointer+int(key,16)
                if key=='98':self.cpu.mem_write(address,bytes([int(value)]))
                elif key in ['1c','58','9c']:self.set_float(address,value)
                else:self.set_integer(address,value)
            self.set_integer(pointer+0x68,self.token(item['reward']) if item['reward'] else 0)
            self.set_integer(pointer+0x7c,123 if core['registered'] else 0)
        self.set_integer(0x107ded00,self.token(rules['fallback_reward']))
        self.set_integer(0x107ded1c,self.token(rules['bonus_reward']))

    def snapshot(self):
        result=[]
        for handle in self.active:
            item=copy.deepcopy(self.original[handle])
            pointer=self.POOL+handle*0xa8
            item['source_id']=self.integer(pointer+4)
            item['core']['position']=list(struct.unpack('<3f',self.cpu.mem_read(pointer+0x44,12)))
            item['core']['source_slots']['60']=self.integer(pointer+0x60)
            item['core']['source_slots']['58']=self.float(pointer+0x58)
            result.append(item)
        return result

    def advance(self,step,rules):
        self.step=step
        self.events=[]
        self.removed=[]
        self.status_calls=0
        self.set_integer(0x10d9b664,self.profile('mode',0))
        self.set_float(0x105d8be8,rules['open_seconds'])
        self.set_float(0x105d8bec,rules['disappear_seconds'])
        self.set_float(0x105d04d8,rules['mission_score'])
        action=step.get('action','advance')
        output=None
        if action=='advance':
            self.call(0x10153370,[word(step.get('delta',.1))])
            output=dict(ok=True,removed=self.removed,totals=dict(base=self.integer(0x10f1baf0),visible=self.integer(0x10f1bae8),story=self.integer(0x10f1baec)))
        else:
            handle=step.get('handle',self.active[0])
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.POOL+handle*0xa8)
            if action=='exposed':output=bool(self.call(0x101520c0))
            elif action=='begin_open':
                output=self.integer(self.POOL+handle*0xa8+0x60)==0
                self.call(0x10152a30)
            else:raise ValueError('Unknown action')
        return dict(output=output,chests=self.snapshot(),events=self.events,unlocks=sorted(self.unlocks),opened_count=self.integer(0x10f27f94))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_chest_lifetime.json'))
    args=parser.parse_args()
    content=extract()
    rules=content['lifetime_rules']
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    oracle=LifetimeOracle(raw)
    oracle.configure_lifetime()
    expose=dict(action='exposed')
    begin=dict(action='begin_open')
    cases=[dict(name='full_lifetime',chests=[chest()],steps=[expose,begin]+[dict(delta=.5) for _ in range(6)]),
           dict(name='no_repeated_reward',chests=[chest(phase=1)],steps=[dict(delta=1.),dict(delta=.01),dict(delta=0.),dict(delta=.1),dict(delta=.9)]),
           dict(name='phase_two_exact',chests=[chest(phase=2,elapsed=1.)],steps=[dict(delta=1.),dict(delta=.001)]),
           dict(name='raw_reopen',chests=[chest(phase=1,elapsed=.75)],steps=[begin,dict(delta=.5),begin]),
           dict(name='empty',chests=[],steps=[dict(delta=.1)]),
           dict(name='multiple_release',chests=[chest(0,phase=2,elapsed=2.),chest(1),chest(2,phase=2,elapsed=2.)],steps=[dict(delta=.1),dict(delta=.1)]),
           dict(name='closed_totals',chests=[chest(0),chest(1,kind=4),chest(2,phase=1)],authored_words=17,steps=[dict(delta=0.),dict(delta=0.,influence=False)])]
    for phase in [0,1,2]:
        for height in [5.8,5.9,6.,6.1,6.2]:
            cases.append(dict(name=f'exposure_{phase}_{height}',chests=[chest(phase=phase,height=height)],steps=[expose]))
    cases.extend([dict(name='sculpt_exposure',chests=[chest()],sculpt_active=True,steps=[dict(expose,sculpt_height=19.),dict(expose,sculpt_height=20.),dict(expose,sculpt_height=21.)]),
                  dict(name='negative_coordinate',chests=[chest(x=-.75,z=120.75)],steps=[expose]),
                  dict(name='follow_lowered_ground',chests=[chest()],ground=3.,steps=[dict(delta=.1) for _ in range(5)]),
                  dict(name='stay_buried_after_raise',chests=[chest()],ground=6.3,steps=[dict(delta=.1) for _ in range(3)]),
                  dict(name='zero_delta_height_response',chests=[chest()],ground=5.,steps=[dict(delta=0.)]),
                  dict(name='mission_score',chests=[chest(kind=4)],mission_mode=3,steps=[begin]),
                  dict(name='fractional_score',chests=[chest()],mission_mode=3,rules=dict(mission_score=100.75),steps=[begin])])
    for name,options in [('ordinary',{}),('fallback_zero',dict(reward=0)),('fallback_missing',dict(reward_available=False)),
                         ('bonus_first',dict(reward_type_a=True)),('bonus_later',dict(reward_type_a=True,unlocks=['CHEST_BONUS_1'])),
                         ('bonus_type_b',dict(reward_type_b=True,unlocks=['CHEST_BONUS_1'],reward_status=[False,True])),
                         ('bonus_unlocked_by_grant',dict(reward_type_a=True,unlock_during_grant=True)),
                         ('no_bonus_type',dict(unlocks=['CHEST_BONUS_1'])),('status_flag',dict(reward_status=True)),
                         ('mode1_sentinel',dict(mode=1,uid_low=0xffffffff,uid_high=0xffffffff)),
                         ('mode1_valid',dict(mode=1,uid_low=0xffffffff,uid_high=1)),
                         ('mode2_not_ready',dict(mode=2)),('mode2_unavailable',dict(mode=2,mode2_ready=True)),
                         ('mode2_ready',dict(mode=2,mode2_ready=True,mode2_available=True)),('mode3',dict(mode=3))]:
        options=copy.deepcopy(options)
        initial=chest(phase=1,elapsed=1.,reward=options.pop('reward','Reward_RandomStickerOrGem'),uid_low=options.pop('uid_low',0),uid_high=options.pop('uid_high',0))
        cases.append(dict(name='reward_'+name,chests=[initial],steps=[dict(delta=.1)],**options))
    for case in cases:
        current=dict(rules,**case.get('rules',{}))
        oracle.load(case,current)
        case['states']=[]
        for index,step in enumerate(case['steps']):
            try:case['states'].append(oracle.advance(step,current))
            except Exception as error:
                raise ValueError(f"Native chest case {case['name']} step {index} at {hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))}; services {list(map(hex,oracle.trace))}") from error
    result=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],cases=cases,
                native_routines={key:content['native_routines'][key] for key in ['0x101520c0','0x10152a30','0x10153370','0x101521b0']},
                adapters=[hex(a) for a in sorted(oracle.adapters)],observation_hooks=['0x101521b0','0x10152ae4'],scope=__doc__.strip())
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original chest lifetime:',len(cases),'cases,',sum(len(c['steps']) for c in cases),'transitions',flush=True)


if __name__=='__main__':main()
