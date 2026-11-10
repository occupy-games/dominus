"""Execute the complete original reward dispatcher and temple/chest wrappers.

Native story scans, set/map lookup walks, set iteration, recursive five-slot
packs, type helpers, flag changes and all dispatch branches execute. Only tree
storage/allocation, CRT words, story delivery, final credit/refresh and selector
services are adapters. The original entrypoint, devices and OS never execute.
"""
import copy
import json
import random
import struct

from tools.native_scenery_oracle import Oracle, ROOT
from tools.reward_dispatch import extract, key
from tools.native_temple_repair_oracle import state as temple_state


class DispatchOracle(Oracle):
    def configure_dispatch(self,content):
        self.content=content
        self.adapters={0x10001020:self.allocate,0x103454b0:self.allocate,
                       0x1004fa00:self.insert,0x103571c0:lambda:self.return_integer(),
                       0x1001bf40:lambda:self.return_integer(pop=4),
                       0x1004faa0:self.story,0x1035f7f0:self.word,
                       0x10050170:self.grant,0x100015b0:self.acquired,
                       0x1004de10:self.select_sticker,0x1004dd20:self.select_event,
                       0x1019a930:self.refresh,0x10024700:self.context,
                       0x1035fde0:self.format_unlock,0x1015cd60:self.unlock}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        for address in [0x1003af00,0x10051520]:
            self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe,begin=address,end=address))
        self.temple_site=0
        # The supplied hash routines execute independently of Python's decoder.
        for symbol in [*content['symbols'].values(),*content['selectors']]:
            self.cpu.mem_write(self.SCRATCH+0x1000,symbol['name'].encode()+b'\0')
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.SCRATCH+0x2000)
            self.call(0x101b51e0,[self.SCRATCH+0x1000])
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.SCRATCH+0x2000)
            if self.call(0x101b5260)!=symbol['id']:raise ValueError('Source hash mismatch '+symbol['name'])
        for symbol in content['selectors']:
            self.set_integer(int(symbol['address'],16),symbol['id'])
        event=content['symbols']['event_reward']
        self.set_integer(int(event['address'],16),event['id'])

    def event(self,name,args=()):
        count=struct.unpack('<i',self.cpu.mem_read(0x107decd4,4))[0]
        event=[name,list(args),count,self.integer(0x107decd8)]
        if self.temple_site:event.append([self.integer(self.temple_site+0x2fc),self.integer(self.temple_site+0x238),bool(self.cpu.mem_read(self.temple_site+0x2c0,1)[0])])
        self.events.append(event)

    def observe(self,cpu,address,size,user):
        if not self.temple_site:return
        if address==0x1003af00:self.event('is_discovery')
        else:self.event('grant_temple',self.arguments(3))

    def context(self):
        self.event('notification_context')
        if 'context_source_id' in self.case:self.set_integer(self.temple_site+0x10,self.case['context_source_id'])
        self.return_integer(self.SCRATCH+0x6000)

    def format_unlock(self):
        target,format,identity=self.arguments(3)
        template=bytes(self.cpu.mem_read(format,80)).split(b'\0')[0].decode()
        if template!='TEMPLE_COMPLETE_%d':raise ValueError('Unexpected unlock template')
        identity=struct.unpack('<i',struct.pack('<I',identity))[0]
        self.unlock_name=template%identity
        self.cpu.mem_write(target,self.unlock_name.encode()+b'\0')
        self.return_integer(len(self.unlock_name))

    def unlock(self):
        if self.arguments(1)[0]!=key(self.unlock_name):raise ValueError('Original completion unlock hash mismatch')
        self.event('unlock',[self.unlock_name])
        for name,offset in [('unlock_reward',0x234),('unlock_source_id',0x10)]:
            if name in self.case:self.set_integer(self.temple_site+offset,self.case[name])
        self.return_integer()

    def allocate(self):
        self.return_integer(self.alloc(self.arguments(1)[0]))

    def alloc(self,size):
        result=self.heap
        self.heap+=(size+15)&~15
        if self.heap>self.POOL+0x1000000:raise ValueError('Controlled heap exhausted')
        self.cpu.mem_write(result,bytes((size+15)&~15))
        return result

    def tree(self,header,entries):
        if header not in self.nodes:self.nodes[header]={}
        self.trees[header]=dict(entries)
        for identity in entries:
            if identity not in self.nodes[header]:self.nodes[header][identity]=self.alloc(0x20)
        ids=sorted(entries)
        def branch(ids,parent):
            if not ids:return 0
            middle=len(ids)//2
            identity=ids[middle]
            pointer=self.nodes[header][identity]
            self.cpu.mem_write(pointer,bytes(0x20))
            self.set_integer(pointer+4,parent)
            self.set_integer(pointer+8,branch(ids[:middle],pointer))
            self.set_integer(pointer+12,branch(ids[middle+1:],pointer))
            self.set_integer(pointer+16,identity)
            self.set_integer(pointer+20,entries[identity])
            return pointer
        self.set_integer(header+4,branch(ids,header))
        self.set_integer(header+8,self.nodes[header][ids[0]] if ids else header)
        self.set_integer(header+12,self.nodes[header][ids[-1]] if ids else header)

    def install(self,address,entries):
        header=self.alloc(0x20)
        self.set_integer(address,header)
        self.set_integer(address+4,len(entries))
        self.tree(header,entries)
        return header

    def insert(self):
        target=self.cpu.reg_read(self.regs.UC_X86_REG_ECX)
        output,value=self.arguments(2)
        identity=self.integer(value)
        header=self.integer(target)
        entries=dict(self.trees.get(header,{}))
        fresh=identity not in entries
        entries[identity]=0
        self.tree(header,entries)
        self.set_integer(target+4,len(entries))
        self.set_integer(output,self.nodes[header][identity])
        self.cpu.mem_write(output+4,bytes([int(fresh)]))
        self.return_integer(output,pop=8)

    def story(self):self.event('story',self.arguments(1));self.return_integer()
    def word(self):
        words=self.case.get('words',[0])
        result=words[self.random_calls%len(words)]
        self.random_calls+=1
        self.return_integer(result)
    def acquired(self):
        identity,=self.arguments(1)
        self.event('card_acquired',[identity])
        self.return_integer(self.counts.get(identity,0))
    def grant(self):
        identity,sticker,flags,reason,source=self.arguments(5)
        self.event('grant',[identity,bool(sticker),flags,reason,source])
        if self.case.get('credit_updates_count',False):self.counts[identity]=(self.counts.get(identity,0)+1)&0xffffffff
        self.return_integer(pop=20)
    def select_sticker(self):
        identity,override=self.arguments(2)
        self.event('select_sticker',[identity,override])
        self.return_integer(self.case.get('selected_sticker',0))
    def select_event(self):self.event('select_event_reward');self.return_integer(self.case.get('selected_event',0))
    def refresh(self):self.event('refresh');self.return_integer()

    def load(self,case):
        self.case=case
        self.temple_site=0
        self.events=[]
        self.random_calls=0
        self.heap=self.POOL+0x10000
        self.trees={}
        self.nodes={}
        self.counts={int(k):v for k,v in case.get('counts',{}).items()}
        current=case.get('state',dict(stories_acquired=[],pack_count=0,pack_index=0))
        self.collected=self.install(0x10f07ed0,{identity:0 for identity in current['stories_acquired']})
        self.set_integer(0x107decd4,current['pack_count'])
        self.set_integer(0x107decd8,current['pack_index'])
        self.set_float(0x105a1588,case.get('story_chance',self.content['rules']['story_chance']))
        records=case['records']
        if len(records['stories'])>32:raise ValueError('Original story table has 32 slots')
        self.cpu.mem_write(0x10f07c44,bytes(32*0x14))
        for i,story in enumerate(records['stories']):
            for offset,name in [(0,'id'),(8,'essential'),(16,'order')]:self.set_integer(0x10f07c44+i*0x14+offset,story[name])
        self.set_integer(0x10f07ee0,len(records['stories']))
        self.install(0x10f07ec4,{entry['id']:0 for entry in records['stories']})
        packs={}
        for pack in records['packs']:
            pointer=self.alloc(0x40)
            for i,slot in enumerate(pack['slots']):
                self.set_integer(pointer+0x14+i*8,slot['count'])
                self.set_integer(pointer+0x18+i*8,slot['reward'])
            packs[pack['id']]=pointer
        self.install(0x10f06c2c,packs)
        cards={}
        self.cpu.mem_write(0x10f0b30c,bytes(256*0x38))
        for i,card in enumerate(records['cards']):
            pointer=0x10f0b30c+i*0x38
            for offset,name in [(0,'id'),(0xc,'type'),(0x2c,'silent')]:self.set_integer(pointer+offset,card[name])
            cards[card['id']]=pointer
        self.install(0x10f0eb0c,cards)
        stickers={}
        self.cpu.mem_write(0x10f07ef0,bytes(256*0x24))
        for i,sticker in enumerate(records['stickers']):
            pointer=0x10f07ef0+i*0x24
            self.set_integer(pointer,sticker['id'])
            stickers[sticker['id']]=pointer
        self.install(0x10f0a2f0,stickers)

    def snapshot(self):
        return dict(stories_acquired=sorted(self.trees[self.collected]),
                    pack_count=struct.unpack('<i',self.cpu.mem_read(0x107decd4,4))[0],pack_index=self.integer(0x107decd8))

    def run_case(self,case):
        self.load(case)
        action=case.get('action','dispatch')
        if action=='temple_pending':return self.run_pending(case)
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,0x10f18cd0)
        args=[case['reward'],case.get('source_id',1012),case.get('flags',0)]
        if action=='dispatch':self.call(0x10050930,[*args,case.get('reason',8),case.get('override',0)],limit=2000000)
        else:self.call(0x10051520 if action=='temple' else 0x100514f0,args,limit=2000000)
        return dict(state=self.snapshot(),events=self.events,random_calls=self.random_calls,
                    counts={str(k):v for k,v in self.counts.items()})

    def temple_snapshot(self):
        result=copy.deepcopy(self.case['temple'])
        for name,offset in [('phase',0x2fc),('reward_pending',0x238),('reward',0x234)]:result[name]=self.integer(self.temple_site+offset)
        result['source_id']=struct.unpack('<i',self.cpu.mem_read(self.temple_site+0x10,4))[0]
        result['reward_ready']=bool(self.cpu.mem_read(self.temple_site+0x2c0,1)[0])
        return result

    def run_pending(self,case):
        self.temple_site=self.POOL+0x5000
        self.cpu.mem_write(self.temple_site,bytes(0x43c))
        for name,offset in [('phase',0x2fc),('source_id',0x10),('reward_pending',0x238),('reward',0x234)]:self.set_integer(self.temple_site+offset,case['temple'][name])
        self.cpu.mem_write(self.temple_site+0x2c0,bytes([int(case['temple']['reward_ready'])]))
        self.set_integer(0x107d1af0,1)
        self.set_integer(0x107d1aec,self.content['rules']['discovery_type'])
        self.set_integer(self.temple_site+0x30c,self.content['rules']['discovery_type'] if case.get('is_discovery',True) else 0xdeadbeef)
        states=[]
        for _ in range(case.get('steps',2)):
            self.events=[]
            frame=self.STACK+0x80000
            self.cpu.reg_write(self.regs.UC_X86_REG_ESP,frame-0x200)
            self.cpu.reg_write(self.regs.UC_X86_REG_EBP,frame)
            self.cpu.reg_write(self.regs.UC_X86_REG_ESI,self.temple_site)
            self.cpu.reg_write(self.regs.UC_X86_REG_EBX,0)
            self.cpu.emu_start(0x10140b9c,0x10140c0f,count=2000000)
            if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=0x10140c0f:raise ValueError('Deferred temple budget exhausted')
            states.append(dict(temple=self.temple_snapshot(),state=self.snapshot(),events=self.events,random_calls=self.random_calls,
                               counts={str(k):v for k,v in self.counts.items()}))
        return states


def empty():return dict(stories=[],packs=[],cards=[],stickers=[])
def pack(identity,slots):return dict(id=identity,slots=[dict(count=count,reward=reward) for count,reward in slots]+[dict(count=0,reward=0)]*(5-len(slots)))


def cases(content):
    rules=content['rules']
    examples=[]
    stories=[dict(id=900,essential=1,order=2),dict(id=300,essential=0,order=0),dict(id=800,essential=1,order=1),dict(id=100,essential=0,order=0)]
    for kind in ['next_story','random_side_story','random_story']:
        for acquired in [[],[800],[800,900],[100,300],[100,300,800,900],[123]]:
            for word in [0,9830,9831,32767]:
                records=empty();records['stories']=copy.deepcopy(stories)
                examples.append(dict(name=f'{kind}_{acquired}_{word}',reward=rules[kind],records=records,words=[word,32767],
                                     state=dict(stories_acquired=acquired,pack_count=0,pack_index=0)))
    for name,extra in [('unknown',{}),('direct_story',dict(reward=300)),
                       ('empty_next',dict(reward=rules['next_story'],records=empty())),
                       ('order_boundary',dict(reward=rules['next_story'],records=dict(empty(),stories=[dict(id=30,essential=1,order=1000000)]))),
                       ('negative_order',dict(reward=rules['next_story'],records=dict(empty(),stories=[dict(id=30,essential=1,order=-1)]))),
                       ('order_tie',dict(reward=rules['next_story'],records=dict(empty(),stories=[dict(id=30,essential=1,order=1),dict(id=20,essential=1,order=1)]))),
                       ('duplicate_story',dict(reward=rules['random_side_story'],records=dict(empty(),stories=[dict(id=30,essential=0,order=0),dict(id=30,essential=0,order=0),dict(id=20,essential=0,order=0)])))]:
        case=dict(name=name,reward=999,records=dict(empty(),stories=copy.deepcopy(stories)))
        case.update(extra);examples.append(case)
    for card_type in [0,1,2,3,0xffffffff]:
        for silent in [0,1,2,3]:
            for count in [0,1]:
                records=dict(empty(),cards=[dict(id=50,type=card_type,silent=silent)])
                examples.append(dict(name=f'card_{card_type}_{silent}_{count}',reward=50,records=records,counts={'50':count},flags=4))
    for kind in rules['sticker_selectors']+[rules['event_reward']]:
        for selected in [0,60,50,777]:
            records=dict(empty(),cards=[dict(id=50,type=2,silent=0)],stickers=[dict(id=60)])
            examples.append(dict(name=f'selector_{kind}_{selected}',records=records,reward=kind,selected_sticker=selected,selected_event=selected,override=0xffffffff))
    base=dict(empty(),cards=[dict(id=50,type=1,silent=1)],stickers=[dict(id=60)],stories=copy.deepcopy(stories))
    for action in ['dispatch','chest','temple']:
        records=copy.deepcopy(base)
        records['packs']=[pack(70,[(2,50),(1,60),(1,800),(0,60),(-1,60)])]
        examples.append(dict(name='five_slots_'+action,action=action,records=records,reward=70,credit_updates_count=True,flags=4,source_id=0xffffffff))
    records=copy.deepcopy(base)
    records['packs']=[pack(70,[(2,71),(1,60)]),pack(71,[(2,50),(1,60)])]
    examples.append(dict(name='nested_pack',records=records,reward=70,credit_updates_count=True))
    # Overlapping source registries must route independently and retain flags.
    records=dict(empty(),cards=[dict(id=50,type=1,silent=2)],stickers=[dict(id=50)],stories=[dict(id=50,essential=0,order=0)],packs=[pack(50,[(1,60)])])
    examples.append(dict(name='overlapping_registries',records=records,reward=50))
    rng=random.Random(0x10050930)
    for i in range(80):
        records=dict(empty(),stories=[dict(id=rng.randrange(1,0xffffffff),essential=rng.randrange(2),order=rng.randrange(-1,8)) for _ in range(rng.randrange(1,20))])
        examples.append(dict(name='mixed_story_'+str(i),records=records,reward=rules[rng.choice(['next_story','random_story','random_side_story'])],
                             words=[rng.randrange(32768) for _ in range(10)],story_chance=rng.choice([0.,.3,1.]),
                             state=dict(stories_acquired=[entry['id'] for entry in records['stories'] if rng.randrange(3)==0],pack_count=3,pack_index=2)))
    # Actual recovered source pack contents, not just controlled pack examples.
    for row in content['tables']['initialworldsetup/packdata.csv'][1:]:
        if not row or not row[0].startswith('Pack_'):continue
        slots=[(int(row[4+2*i] or 0),key(row[5+2*i])) for i in range(5)]
        records=dict(empty(),packs=[pack(key(row[0]),slots)],stickers=[dict(id=key('Sticker_Gem_1'))])
        examples.append(dict(name=row[0],records=records,reward=key(row[0]),selected_sticker=key('Sticker_Gem_1'),action='temple'))
    return examples


def pending_cases(content):
    examples=[]
    for phase in range(9):
        for pending in [0,1,0xffffffff]:
            for discovery in [False,True]:
                temple=dict(temple_state(phase),reward=50,reward_pending=pending,reward_ready=bool(pending))
                examples.append(dict(name=f'pending_{phase}_{pending}_{discovery}',action='temple_pending',temple=temple,is_discovery=discovery,
                                     records=dict(empty(),cards=[dict(id=50,type=2,silent=0)])))
    for name,extra in [('zero_reward',dict(temple=dict(temple_state(7),reward=0,reward_pending=1,reward_ready=True))),
                       ('context_changes_id',dict(context_source_id=-2147483648)),
                       ('unlock_changes_reward',dict(unlock_reward=60)),
                       ('unlock_clears_reward',dict(unlock_reward=0)),
                       ('unlock_changes_id',dict(unlock_source_id=-1)),
                       ('flag_independent',dict(temple=dict(temple_state(7),reward=50,reward_pending=1,reward_ready=False)))]:
        case=dict(name=name,action='temple_pending',temple=dict(temple_state(7),reward=50,reward_pending=1,reward_ready=True),
                  records=dict(empty(),cards=[dict(id=50,type=2,silent=0)],stickers=[dict(id=60)]))
        case.update(extra);examples.append(case)
    for row in content['tables']['initialworldsetup/packdata.csv'][1:]:
        if not row or not row[0].startswith('Pack_'):continue
        slots=[(int(row[4+2*i] or 0),key(row[5+2*i])) for i in range(5)]
        records=dict(empty(),packs=[pack(key(row[0]),slots)],stickers=[dict(id=key('Sticker_Gem_1'))])
        examples.append(dict(name='discovery_'+row[0],action='temple_pending',records=records,
                             temple=dict(temple_state(7),reward=key(row[0]),reward_pending=1,reward_ready=True),selected_sticker=key('Sticker_Gem_1')))
    return examples


def story_sequences(oracle,content):
    stories=[dict(id=key(row[0]),essential=int(row[2] or 0),order=int(row[4] or 0))
             for row in content['tables']['initialworldsetup6/storypieces.csv'][1:] if row and not row[0].startswith('#')]
    sequences=[]
    for kind in ['next_story','random_story','random_side_story']:
        records=dict(empty(),stories=stories)
        words=[0,32767,9830,9831,12345,22222]
        current=dict(stories_acquired=[],pack_count=0,pack_index=0)
        sequence=dict(kind=content['rules'][kind],name=kind,records=records,words=words,initial=copy.deepcopy(current),steps=[])
        total=0
        for _ in range(28):
            offset=total%len(words)
            case=dict(reward=sequence['kind'],records=records,words=words[offset:]+words[:offset],state=current)
            result=oracle.run_case(case)
            result['random_calls']+=total
            total=result['random_calls']
            sequence['steps'].append(result)
            current=result['state']
        sequences.append(sequence)
    return sequences


def main():
    content=extract()
    oracle=DispatchOracle((ROOT/'data/godus2_4/godus.s86').read_bytes())
    oracle.configure_dispatch(content)
    examples=cases(content)
    for case in examples:
        try:case['expected']=oracle.run_case(case)
        except Exception as error:raise ValueError('Original reward case '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    pending=pending_cases(content)
    for case in pending:
        try:case['expected']=oracle.run_case(case)
        except Exception as error:raise ValueError('Original deferred temple case '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    sequences=story_sequences(oracle,content)
    result=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],cases=examples,
                pending_cases=pending,story_sequences=sequences,native_routines=content['native_routines'],adapters=[hex(a) for a in oracle.adapters],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_reward_dispatch.json').write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Original reward dispatch:',len(examples),'cases,',len(pending),'deferred temple cases',flush=True)


if __name__=='__main__':main()
