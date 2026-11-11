"""Execute original bulk follower shrine propagation and candidate-node release.

The actual active follower/site traversal, mask clearing, containment, OR writes
and temporary-node release instructions run. Source radius/type lookup and the
spatial query's ordered candidate nodes are explicit adapters. This does not
establish the original spatial index or candidate allocation policy.
"""
import copy
import json
import random
import struct

from tools.native_scenery_oracle import ROOT
from tools.native_temple_effects_oracle import EffectsOracle,effect_site,base_words
from tools.temple_effects import extract
from tools.native_temple_terrain_oracle import f32


def state():
    return dict(followers=[dict(handle=i,stats_ref=ref,position=position) for i,ref,position in [
        (0,0,[10.,12.,6.]),(1,1,[22.,12.,100.]),(2,-1,[10.,12.,6.]),(3,0,[40.,40.,6.]),(4,2,[10.,12.,18.])]],
        actors={'0':dict(mask=[55,1],extra_mask=[0x80000000,3]),'1':dict(mask=[15,7],extra_mask=[3,0]),
                '2':dict(mask=[0,0],extra_mask=[0,0]),'9':dict(mask=[777,0x80000000],extra_mask=[1,1])})


def sites():
    return [effect_site(4,follower_modifiers=[3,0]),effect_site(7,follower_modifiers=[0,0x80000000])]


def candidates():
    return {'4':[dict(token=i,follower=handle) for i,handle in enumerate([0,1,2,3,4,-1])],
            '7':[dict(token=i+10,follower=handle) for i,handle in enumerate([0,0,-1,4])]}


class PropagationOracle(EffectsOracle):
    FOLLOWERS=0x31000000
    ACTORS=0x34100000
    NODES=0x10c58e68
    FREE_HEAD=0x10c64e68

    def configure_propagation(self,content):
        self.configure_effects(content);self.adapters[0x1012ec90]=self.spatial_query
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_release,begin=0x1006d1cc,end=0x1006d1cc))

    def actor_masks(self):
        return {identity:{field:[self.integer(pointer+offset+4*i) for i in range(2)] for field,offset in [('mask',0x40),('extra_mask',0x48)]}
                for identity,pointer in self.actor_pointers.items()}

    def record_propagation(self,name,args):
        self.events.append([name,list(args),self.actor_masks(),self.integer(self.FREE_HEAD)])

    def spatial_query(self):
        raw=list(self.arguments(10));args=[raw[0],*[struct.unpack('<f',struct.pack('<I',word))[0] for word in raw[1:4]],*raw[4:]]
        self.record_propagation('query',args)
        pointer=self.cpu.reg_read(self.regs.UC_X86_REG_EDI);handle=(pointer-self.POOL)//0x43c
        result=self.case['candidates'].get(str(handle))
        if not result:self.return_integer();return
        for index,node in enumerate(result):
            pointer=self.NODES+node['token']*12;value=self.GRIDS+0x300000+node['token']*4
            self.set_integer(value,0 if node['follower']==-1 else self.FOLLOWERS+node['follower']*0x13c)
            self.set_integer(pointer,value)
            self.set_integer(pointer+4,self.NODES+result[index+1]['token']*12 if index+1<len(result) else 0)
            self.set_integer(pointer+8,self.NODES+result[-1]['token']*12)
        self.return_integer(self.NODES+result[0]['token']*12)

    def observe_release(self,cpu,address,size,user):
        self.record_propagation('release_candidate',[self.cpu.reg_read(self.regs.UC_X86_REG_EAX)])

    def run_propagation(self,case):
        self.case=case;self.events=[]
        self.prepare_sites(case['sites'],case.get('owners',{}))
        self.actor_pointers={identity:self.ACTORS+index*0x80 for index,identity in enumerate(case['state']['actors'])}
        for identity,pointer in self.actor_pointers.items():
            self.cpu.mem_write(pointer,bytes(0x80))
            for field,offset in [('mask',0x40),('extra_mask',0x48)]:
                for index,word in enumerate(case['state']['actors'][identity][field]):self.set_integer(pointer+offset+index*4,word)
        followers=case['state']['followers']
        self.set_integer(0x10fcd450,self.FOLLOWERS);self.cpu.mem_write(0x10fcd45a,struct.pack('<H',followers[0]['handle'] if followers else 0xffff))
        for index,follower in enumerate(followers):
            pointer=self.FOLLOWERS+follower['handle']*0x13c
            self.cpu.mem_write(pointer,bytes(0x13c))
            self.cpu.mem_write(pointer,struct.pack('<H',followers[index+1]['handle'] if index+1<len(followers) else 0xffff))
            self.set_integer(pointer+0x100,0 if follower['stats_ref']==-1 else self.actor_pointers[str(follower['stats_ref'])])
            for i,value in enumerate(follower['position']):self.set_float(pointer+0x70+i*4,value)
        self.set_integer(self.FREE_HEAD,case.get('free_head',4095))
        self.call(0x1006d050,limit=5000000)
        result=copy.deepcopy(case['state'])
        for identity,masks in self.actor_masks().items():result['actors'][identity].update(masks)
        # Consume the stored result, without invoking the single-actor mask
        # rescan. The original getters read exactly the masks just propagated.
        self.load_effects(self.effect_content['records']);stats={}
        for identity,pointer in self.actor_pointers.items():
            stats[identity]={}
            for table,entry,slot in [('race',0x100342a0,0x10fb77bc),('jobs',0x100343b0,0x10fb8b00)]:
                words=base_words(table);self.cpu.mem_write(self.BASE,struct.pack('<'+'I'*len(words),*words));self.set_integer(slot,self.BASE)
                self.cpu.reg_write(self.regs.UC_X86_REG_ECX,pointer);output=self.SCRATCH+0xc000
                self.call(entry,[output],limit=5000000)
                stats[identity][table]=list(struct.unpack('<'+'I'*len(words),self.cpu.mem_read(output,4*len(words))))
        return dict(state=result,events=copy.deepcopy(self.events),free_head=self.integer(self.FREE_HEAD),stats=stats)


def cases():
    examples=[]
    def add(name,**changes):
        case=dict(name=name,state=state(),sites=sites(),candidates=candidates());case.update(changes);examples.append(case);return case
    add('ordinary')
    add('reverse_sites',sites=list(reversed(sites())))
    add('no_sites',sites=[])
    case=add('zero_masks')
    for current in case['sites']:current['follower_modifiers']=[0,0]
    add('query_null',candidates={'4':None,'7':None})
    add('query_empty',candidates={'4':[],'7':[]})
    add('query_omits_contained',candidates={'4':[dict(token=0,follower=3)],'7':[]})
    case=add('no_attached_actors')
    for follower in case['state']['followers']:follower['stats_ref']=-1
    add('no_followers',state=dict(followers=[],actors=state()['actors']),candidates={'4':None,'7':None})
    for missing in [False,True]:
        case=add('inherited_'+str(missing),owners={} if missing else {'2':dict(x=100.,z=12.,height=6.,radius=12.)})
        for current in case['sites']:current['settlement_id']=2
        case['state']['followers'][0]['position']=[100.,12.,6.]
        case['state']['followers'][1]['position']=[112.,12.,6.]
    rng=random.Random(0x1006d050)
    for index in range(64):
        case=add(f'arithmetic_{index}',free_head=rng.randrange(4096))
        for follower in case['state']['followers']:
            follower['position']=[f32(5+rng.random()*30),f32(5+rng.random()*30),f32(4+rng.random()*20)]
        for current in case['sites']:
            current.update(follower_modifiers=[rng.randrange(0x100000000),rng.randrange(0x100000000)],radius=f32(rng.choice([0.,12.,24.])))
        if index%3==0:case['sites'][0]['follower_modifiers']=[0,0]
        for handle in ['4','7']:
            order=list(range(5));rng.shuffle(order)
            case['candidates'][handle]=[dict(token=i+(20 if handle=='7' else 0),follower=follower) for i,follower in enumerate(order[:rng.randrange(6)])]
    return examples


def main():
    content=extract();oracle=PropagationOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_propagation(content)
    examples=cases()
    for case in examples:
        try:case['expected']=oracle.run_propagation(case)
        except Exception as error:raise ValueError('Original shrine propagation '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    sequences=[]
    for attached in [False,True]:
        sequence=dict(initial=state(),free_head=4095,steps=[]);current=copy.deepcopy(sequence['initial']);free_head=4095
        for index in range(32):
            current['followers'][0]['position']=[f32(10.+index),12.,6.]
            current_sites=sites()
            if index%6 in [0,5]:
                for current_site in current_sites:current_site['follower_modifiers']=[0,0]
            if attached:
                for current_site in current_sites:current_site['settlement_id']=2
            step=dict(sites=current_sites,candidates=candidates(),owners={'2':dict(x=f32(10.+index/2),z=12.,height=6.,radius=12.)} if attached else {},position=current['followers'][0]['position'])
            expected=oracle.run_propagation(dict(step,state=current,free_head=free_head));current=copy.deepcopy(expected['state']);free_head=expected['free_head']
            sequence['steps'].append(dict(step,expected=expected))
        sequences.append(sequence)
    fixture=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],cases=examples,sequences=sequences,
                 rules=content['propagation_rules'],base_rows={table:base_words(table) for table in ['race','jobs']},native_routines=content['native_routines'],adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_temple_propagation.json').write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    print('Original shrine propagation:',len(examples),'cases,',sum(len(s['steps']) for s in sequences),'steps',flush=True)


if __name__=='__main__':main()
