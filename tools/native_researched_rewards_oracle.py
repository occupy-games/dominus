"""Original reward queue consumption composed with unadapted card research."""
import copy
import json
import re
import struct

from tools.card_research import extract as research_content
from tools.native_card_research_oracle import card,sticker
from tools.native_availability_oracle import NativeAvailabilityStorage,empty
from tools.native_reward_queue_oracle import QueueOracle,initial
from tools.reward_queue import extract as queue_content
from tools.native_scenery_oracle import ROOT


class ResearchedRewardsOracle(QueueOracle):
    def configure_researched(self,content):
        self.configure_queue(content)
        for handle in self.handles:self.cpu.hook_del(handle)
        for address in [0x10001360,0x10027330,0x100273d0,0x10027410,0x10028420]:del self.adapters[address]
        self.adapters.update({0x1035fde0:self.format_researched,0x10179af0:self.log_researched,
                              0x100e0590:self.notice,0x100f5280:self.effect})
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        for address in [0x100242f0,0x1019a910,0x10026880]:
            self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_queue,begin=address,end=address))

    def string(self,pointer):return bytes(self.cpu.mem_read(pointer,1024)).split(b'\0')[0].decode()
    def format_researched(self):
        target,template,first,second=self.arguments(4)
        if self.string(template)!='%s%s':return self.format()
        text=self.string(first)+self.string(second)
        self.cpu.mem_write(target,text.encode()+b'\0')
        self.return_integer(len(text))
    def log_researched(self):
        channel,pointer=self.arguments(2)
        if channel==35:self.storage.diagnostic();return
        text=self.string(pointer)
        tokens=re.findall(r'%[iud]',text)
        args=self.arguments(2+len(tokens))[2:]
        args=[value-0x100000000 if token=='%i' and value>=0x80000000 else value for token,value in zip(tokens,args)]
        self.event('log',[channel,text,args])
        self.return_integer()
    def notice(self):
        context,kind,name=self.arguments(3)
        self.event('notice',[context,kind,self.string(name)])
        self.return_integer()
    def effect(self):
        args=self.arguments(7)
        position=list(struct.unpack('<3f',struct.pack('<3I',*args[2:5])))
        self.event('effect',[self.string(args[0]),args[1],position,*args[5:]])
        self.return_integer()

    def load_researched(self,case):
        self.load_queue(case)
        self.storage=NativeAvailabilityStorage(self,case.get('availability',empty()))
        self.cpu.mem_write(0x10f17c0c,bytes([1]))
        self.set_integer(self.SCRATCH+0x6000,12345)
        for i,row in enumerate(case['records']['cards']):
            pointer=0x10f0b30c+i*0x38
            text=self.alloc(len(row['name'].encode())+1)
            self.cpu.mem_write(text,row['name'].encode()+b'\0')
            self.set_integer(pointer+4,text)
            self.set_integer(pointer+0x34,row['happiness'])
        for i,row in enumerate(case['records']['stickers']):
            pointer=0x10f07ef0+i*0x24
            self.cpu.mem_write(pointer+0xc,bytes([int(row['internal'])]))
            for slot in range(2):
                self.set_integer(pointer+0x14+slot*4,row['categories'][slot])
                self.set_integer(pointer+0x1c+slot*4,row['counts'][slot])

    def advance_researched(self,step):
        if step['action'] in ['assign','complete']:
            self.events=[]
            self.storage.events=[]
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,0x10f0b30c)
            address=0x10028420 if step['action']=='assign' else 0x10027410
            args=[step['sticker'],int(step.get('allow_internal',False))] if step['action']=='assign' else []
            value=bool(self.call(address,args,limit=1000000)&255)
            result=dict(value=value,state=self.snapshot_queue(),dispatch=self.snapshot(),availability=self.storage.snapshot(),availability_events=copy.deepcopy(self.storage.events),events=copy.deepcopy(self.events),random_calls=self.random_calls)
        else:
            result=self.advance(step)
            del result['research']
        result['research_context']=dict(cache_valid=bool(self.cpu.mem_read(0x10f17c0c,1)[0]))
        return result


def cases(content):
    examples=[]
    def add(name,row,flags=3,stickers=None,availability=None,steps=None,**extra):
        steps=steps or [dict(action='admit',flags=flags),dict(action='consume'),dict(action='consume')]
        for step in steps:
            if step['action']=='admit':step.setdefault('reward',row['id'])
        examples.append(dict(name=name,records=dict(cards=[row],stickers=stickers or content['stickers'],special=[],stories=[],packs=[]),
                             availability=availability or empty(),steps=steps,**extra))
    for category in range(6):
        for needed in [-1,0,1,3,10]:
            add(f'auto_{category}_{needed}',card(category=category,research_needed=needed))
    for happiness in [-3,-2,-1,0,1,2,3]:add('happiness_'+str(happiness),card(research_needed=0,happiness=happiness),player=3)
    for flags in [0,1,2,3,4,5,6,7,8,10,16,18]:
        add('flags_'+str(flags),card(research_needed=1),flags,steps=[dict(action='admit',flags=flags),dict(action='take'),dict(action='consume'),dict(action='consume')])
    state=empty();state['acquired']['@60']=3
    for count in [0,2,8]:
        add('manual_'+str(count),card(),stickers=[sticker(counts=[count,0])],availability=state,
            steps=[dict(action='temple',reward=50),dict(action='take'),dict(action='consume')]+[dict(action='assign',sticker=60)]*3+[dict(action='complete'),dict(action='consume')])
    for row in content['scopes']['initialworldsetup6']:
        if row['type']==2:add('source_'+row['source_id'],row)
    return examples


def main():
    queue=queue_content()
    research=research_content()
    oracle=ResearchedRewardsOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_researched(queue)
    examples=cases(research)
    for case in examples:
        try:
            oracle.load_researched(case)
            case['states']=[oracle.advance_researched(step) for step in case['steps']]
        except Exception as error:raise ValueError('Researched reward '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    output=dict(executable_sha256=research['executable_sha256'],source_sha256=research['source_sha256'],
                native_routines=dict(queue['native_routines'],**research['native_routines']),adapters=[hex(a) for a in sorted(oracle.adapters)],cases=examples,scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_researched_rewards.json').write_text(json.dumps(output,separators=(',',':'))+'\n')
    print('Original researched rewards:',len(examples),'cases,',sum(len(c['steps']) for c in examples),'transitions')


if __name__=='__main__':main()
