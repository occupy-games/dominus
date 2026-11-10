"""Run original card research and actual map/hash/inventory helpers in memory.

Formatting, diagnostics, notification context and happiness-effect delivery are
adapters. Research predicates, lookup walks, all counter writes and failed-write
ordering execute original instructions. No application entrypoint or OS executes.
"""
import copy
import json
import random
import struct

from tools.card_research import extract,pair_key
from tools.native_availability_oracle import NativeAvailabilityStorage,empty
from tools.native_reward_dispatch_oracle import DispatchOracle
from tools.reward_dispatch import extract as dispatch_content,key
from tools.native_scenery_oracle import ROOT


def card(**extra):return dict(dict(id=50,name='Card_Research_Test',type=2,category=1,research_needed=5,happiness=0,silent=0),**extra)
def sticker(**extra):return dict(dict(id=60,internal=False,categories=[1,0],counts=[2,0]),**extra)
def research_key(row):return key(row['name']+(['','_RES_WAR','_RES_TRADE','_RES_FAITH','_RES_SOCIAL','_RES_TECH'][row['category']] if row['category']<6 else ''))
def completion_key(row):return key(row['name']+'_COMPLETED')
def counters(row=None,owned=1,stickers=3,research=0,**extra):
    row=row or card()
    result=empty()
    result['acquired']={'@'+str(row['id']):owned,'@60':stickers,'@'+str(research_key(row)):research}
    for name,values in extra.items():result[name].update(values)
    return result


class ResearchOracle(DispatchOracle):
    def configure_research(self):
        self.configure_dispatch(dispatch_content())
        for handle in self.handles:self.cpu.hook_del(handle)
        self.adapters={0x10179af0:self.log,0x1035fde0:self.format,0x10024700:self.context,
                       0x100e0590:self.notice,0x1015cc90:self.acquired,0x100f5280:self.effect,
                       0x1035f830:lambda:self.return_integer(self.cpu.reg_read(self.regs.UC_X86_REG_EAX))}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.cpu.mem_write(0x10fbdfe8,bytes(50*8))
        self.call(0x1039dd10)
        self.call(0x1039f070)

    def string(self,pointer):return bytes(self.cpu.mem_read(pointer,1024)).split(b'\0')[0].decode()
    def context(self):
        self.events.append(['context',[]])
        self.set_integer(self.SCRATCH+0x6000,12345)
        self.return_integer(self.SCRATCH+0x6000)
    def notice(self):
        context,kind,name=self.arguments(3)
        self.events.append(['notice',[context,kind,self.string(name)]])
        self.return_integer()
    def acquired(self):self.events.append(['acquired',self.arguments(1)]);self.return_integer()
    def effect(self):
        args=self.arguments(7)
        position=list(struct.unpack('<3f',struct.pack('<3I',*args[2:5])))
        self.events.append(['effect',[self.string(args[0]),args[1],position,*args[5:]]])
        self.return_integer()
    def log(self):
        channel,pointer=self.arguments(2)
        if channel==35:self.storage.diagnostic();return
        text=self.string(pointer)
        count=text.count('%d')
        self.events.append(['log',[channel,text,self.arguments(2+count)[2:]]])
        self.return_integer()
    def format(self):
        target,template,first,second=self.arguments(4)
        if self.string(template)!='%s%s':raise ValueError('Unexpected research format')
        text=self.string(first)+self.string(second)
        self.cpu.mem_write(target,text.encode()+b'\0')
        self.return_integer(len(text))

    def load_research(self,case):
        self.load(dict(records=dict(cards=case['cards'],stickers=case['stickers'],stories=[],packs=[])))
        for i,row in enumerate(case['cards']):
            pointer=0x10f0b30c+i*0x38
            text=self.alloc(len(row['name'].encode())+1)
            self.cpu.mem_write(text,row['name'].encode()+b'\0')
            self.set_integer(pointer+4,text)
            for offset,name in [(0x18,'category'),(0x1c,'research_needed'),(0x34,'happiness')]:self.set_integer(pointer+offset,row[name])
        for i,row in enumerate(case['stickers']):
            pointer=0x10f07ef0+i*0x24
            self.cpu.mem_write(pointer+0xc,bytes([int(row['internal'])]))
            for slot in range(2):
                self.set_integer(pointer+0x14+slot*4,row['categories'][slot])
                self.set_integer(pointer+0x1c+slot*4,row['counts'][slot])
        self.storage=NativeAvailabilityStorage(self,case['availability'])
        self.cpu.mem_write(0x10f17c0c,bytes([int(case.get('cache_valid',True))]))
        self.set_integer(0x10d9b670,case.get('player',0))
        self.cpu.mem_write(0x10fbdfe8,bytes(50*8))
        for i,identity in enumerate(case.get('exempt',[0])):self.set_integer(0x10fbdfe8+i*8,identity)

    def step_research(self,step):
        self.events=[]
        self.storage.events=[]
        action=step['action']
        args=[]
        if action=='register':
            self.call(0x10001870,[step['key'],step['stock'],step['acquisition']])
            value=True
        else:
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,0x10f0b30c+step.get('card',0)*0x38)
            routines=dict(research_key=0x100268a0,combination_key=0x10026950,completion_key=0x100269b0,
                          completed=0x10026f40,progress=0x10026fa0,remaining=0x10027330,ready=0x100273d0,
                          can_assign=0x10028230,assign=0x10028420,complete=0x10027410)
            if action=='combination_key':args=[step.get('sticker',60)]
            if action in ['can_assign','assign']:args=[step.get('sticker',60),int(step.get('allow_internal',False))]
            value=self.call(routines[action],args,floating=action=='progress',limit=300000)
            if action in ['completed','ready','can_assign','assign','complete']:value=bool(value&255)
        return dict(value=value,availability=self.storage.snapshot(),events=copy.deepcopy(self.events),
                    availability_events=copy.deepcopy(self.storage.events),cache_valid=bool(self.cpu.mem_read(0x10f17c0c,1)[0]))


def cases(content):
    result=[]
    def add(name,row=None,stickers=None,availability=None,steps=None,**extra):
        row=row or card()
        result.append(dict(name=name,cards=[row],stickers=stickers if stickers is not None else [sticker()],
                           availability=availability if availability is not None else counters(row),
                           steps=steps if steps is not None else [dict(action=a) for a in ['completed','progress','remaining','ready','can_assign','assign','remaining','assign','assign','ready','complete','completed','remaining','assign','complete']],**extra))
    add('ordinary_research')
    for amount in [-2147483648,-1,0,1,2,5,99999,2147483647]:add('needed_'+str(amount),card(research_needed=amount))
    for kind in [0,1,3,4,0xffffffff]:add('type_'+str(kind),card(type=kind))
    for category in [0,1,2,3,4,5,6,0xffffffff]:
        add('category_'+str(category),card(category=category),[sticker(categories=[category,0])])
    for happiness in [-4,-3,-2,-1,0,1,2,3,4,2147483647]:add('happiness_'+str(happiness),card(research_needed=1,happiness=happiness))
    add('secondary_category',stickers=[sticker(categories=[2,1],counts=[90,3])])
    add('duplicate_category_first_wins',stickers=[sticker(categories=[1,1],counts=[1,90])])
    add('zero_contribution',stickers=[sticker(counts=[0,0])])
    add('unowned_sticker',availability=counters(stickers=0))
    add('unacquired_card',availability=counters(owned=0))
    add('spent_card',availability=counters(spent={'@50':1}))
    add('owned_card_underflow',availability=counters(owned=0,spent={'@50':1}))
    add('sticker_owned_underflow',availability=counters(stickers=0,spent={'@60':1}))
    add('no_sticker_definition',stickers=[])
    add('zero_sticker',steps=[dict(action=a,sticker=0) for a in ['can_assign','assign']])
    for internal in [False,True]:
        add('internal_'+str(internal),stickers=[sticker(internal=True)],steps=[dict(action=a,allow_internal=internal) for a in ['can_assign','assign','remaining','assign','assign','complete']])
    for name in ['', 'Card_Case', 'card_case', 'Carte_épreuve', 'A'*256]:
        add('name_'+name,row=card(name=name),steps=[dict(action=a) for a in ['research_key','combination_key','completion_key','progress']])
    for amount in [0,1,4,5,6,99999,16777217,0x7fffffff,0x80000000,0xffffffff]:
        add('owned_research_'+str(amount),availability=counters(research=amount))
    for name,target in [('combination',pair_key(50,60)),('research',research_key(card())),('completion',completion_key(card()))]:
        for cap in [0,1,2]:
            state=counters(research=5 if name=='completion' else 0)
            for kind in ['stock','acquisition']:
                state[kind+'_registered']['@'+str(target)]=True
                state[kind+'_limits']['@'+str(target)]=cap
            add('limit_'+name+'_'+str(cap),availability=state)
    state=counters(research=5,acquired={'@'+str(completion_key(card())):1},spent={'@'+str(completion_key(card())):1})
    add('spent_completion_still_complete',availability=state)
    for stock,acquisition in [(9,3),(0,7),(0xffffffff,0xffffffff)]:
        add('register_'+str(stock)+'_'+str(acquisition),availability=empty(),steps=[dict(action='register',key=17,stock=stock,acquisition=acquisition),dict(action='register',key=17,stock=99,acquisition=99)])
    state=empty();state['stock_registered']['@17']=True;state['stock_limits']['@17']=3
    add('register_existing_stock_only',availability=state,steps=[dict(action='register',key=17,stock=99,acquisition=99)])
    # Every recovered advance runs real research/assignment/completion. Internal
    # stickers provide their original category, with no substitute contribution.
    for scope,cards in content['scopes'].items():
        for row in cards:
            if row['type']!=2:continue
            compatible=next((s for s in content['stickers'] if s['internal'] and row['category'] in s['categories'] and s['id']),None)
            state=counters(row,stickers=0,research=max(0,row['research_needed']-1))
            if compatible:state['acquired']['@'+str(compatible['id'])]=1
            steps=[dict(action='remaining'),dict(action='assign',sticker=compatible['id'] if compatible else 0,allow_internal=True),dict(action='complete'),dict(action='completed')]
            add('source_'+scope+'_'+row['source_id'],row,content['stickers'],state,steps)
    rng=random.Random(0xc4ad)
    for i in range(160):
        row=card(id=rng.randrange(1,0x100000000),category=rng.randrange(7),research_needed=rng.randrange(-2,12),happiness=rng.randrange(-4,5))
        state=counters(row,owned=rng.randrange(3),stickers=rng.randrange(5),research=rng.randrange(15))
        add('random_'+str(i),row,[sticker(categories=[rng.randrange(7),rng.randrange(7)],counts=[rng.randrange(8),rng.randrange(8)],internal=bool(i&1))],state)
    return result


def main():
    content=extract()
    oracle=ResearchOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_research()
    examples=cases(content)
    for case in examples:
        oracle.load_research(case)
        case['states']=[oracle.step_research(step) for step in case['steps']]
    output=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],
                native_routines=content['native_routines'],adapters=[hex(a) for a in sorted(oracle.adapters)],cases=examples,
                scope='Complete original research helpers and actual native fixed-map storage, hashes and inventory. Only format, log, notification and effect services are adapted.')
    (ROOT/'game/tests/fixtures/source_card_research.json').write_text(json.dumps(output,indent=2)+'\n')
    print('Original card research:',len(examples),'cases,',sum(len(c['steps']) for c in examples),'transitions')


if __name__=='__main__':main()
