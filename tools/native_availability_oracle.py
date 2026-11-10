"""Compare original reward capacity/ownership instructions with plain tables.

Only diagnostic output is adapted in the primary comparison. Original fixed-map
lookup/insertion, registration-bucket walks, default-limit writes, query order and unsigned arithmetic execute. This
does not execute reward selection, redemption, any entrypoint or OS service.
"""
import argparse
import copy
import json
import random

from tools.native_scenery_oracle import Oracle, ROOT
from tools.storm_chests import extract
from tools.native_chest_lifetime_oracle import LifetimeOracle, chest


TABLES = {0x1062acd0:'stock_limits',0x1065ccd8:'acquisition_limits',
          0x106c0ce8:'acquired',0x1068ece0:'spent'}
REGISTRIES = {0x1065acd0:'stock_registered',0x1068ccd8:'acquisition_registered'}
ROUTINES = {0x10001360:0x100013da,0x10001480:0x1000153c,0x100015b0:0x10001661}


def empty():return {name:{} for name in [*TABLES.values(),*REGISTRIES.values()]}
def canonical(value):return value if isinstance(value,str) else '@'+str(value)


class AvailabilityStorage:
    """Storage-only adapter, reusable inside composed original routine calls."""
    def __init__(self,oracle,state,tokens=None,base=None):
        self.oracle=oracle
        self.state=copy.deepcopy(state)
        self.base=oracle.GRIDS if base is None else base
        self.tokens={} if tokens is None else dict(tokens)
        self.names={value:canonical(key) for key,value in self.tokens.items()}
        self.cells={}
        self.events=[]
        for address,table in REGISTRIES.items():
            oracle.cpu.mem_write(address,bytes(2048*4))
            for key,registered in self.state[table].items():
                if not registered:continue
                token=self.token(key)
                bucket=address+(token&2047)*4
                pointer=self.base+0x10000+len(self.cells)*16
                # Registry records and counter records use distinct pools.
                self.cells[('registry',table,key)]=pointer
                oracle.set_integer(pointer,token)
                oracle.set_integer(pointer+8,oracle.integer(bucket))
                oracle.set_integer(bucket,pointer)
                kind=table.removesuffix('_registered')
                self.state[kind+'_limits'].setdefault(key,0)
        for table in TABLES.values():
            for key,value in self.state[table].items():self.cell(table,key,value)

    def token(self,key):
        key=canonical(key)
        if key.startswith('@') and key[1:].isdigit():return int(key[1:])
        if key not in self.tokens:
            value=0x10000000+len(self.tokens)
            while value in self.names:value+=1
            self.tokens[key]=value
            self.names[value]=key
        return self.tokens[key]

    def name(self,token):return self.names.get(token,'@'+str(token))

    def cell(self,table,key,value=0):
        identity=(table,key)
        if identity not in self.cells:
            pointer=self.base+len(self.cells)*16
            self.cells[identity]=pointer
            self.oracle.set_integer(pointer,value)
        return self.cells[identity]

    def lookup(self):
        oracle=self.oracle
        table=TABLES[oracle.cpu.reg_read(oracle.regs.UC_X86_REG_ECX)]
        key=self.name(oracle.arguments(1)[0])
        if table in ['stock_limits','acquisition_limits']:
            kind=table.removesuffix('_limits')
            registry=kind+'_registered'
            if not self.state[registry].get(key,False):
                token=self.token(key)
                address=next(address for address,name in REGISTRIES.items() if name==registry)
                bucket=address+(token&2047)*4
                pointer=self.base+0x10000+len(self.cells)*16
                self.cells[('registry',registry,key)]=pointer
                oracle.set_integer(pointer,token)
                oracle.set_integer(pointer+8,oracle.integer(bucket))
                oracle.set_integer(bucket,pointer)
                self.state[registry][key]=True
        self.state[table].setdefault(key,0)
        oracle.return_integer(self.cell(table,key),pop=4)

    def diagnostic(self):
        channel,format,token=self.oracle.arguments(3)
        if channel!=35 or format not in [0x104a0748,0x104a0790]:raise ValueError('Unexpected limit diagnostic')
        self.events.append(dict(type='unregistered_limit',kind='stock' if format==0x104a0748 else 'acquisition',key=self.name(token)))
        self.oracle.return_integer()

    def snapshot(self):
        for identity,pointer in self.cells.items():
            if identity[0]!='registry':self.state[identity[0]][identity[1]]=self.oracle.integer(pointer)
        return copy.deepcopy(self.state)


class NativeAvailabilityStorage(AvailabilityStorage):
    """Load real native map bodies; lookup/insertion executes original code."""
    def __init__(self,oracle,state):
        self.oracle=oracle
        self.state=copy.deepcopy(state)
        self.tokens={}
        self.names={}
        self.events=[]
        self.cells={}
        for address,table in TABLES.items():
            oracle.cpu.mem_write(address,bytes(0x32008))
            entries=dict(self.state[table])
            if table in ['stock_limits','acquisition_limits']:
                registry=table.removesuffix('_limits')+'_registered'
                entries={key:self.state[table].get(key,0) for key,value in self.state[registry].items() if value}
            for index,(name,value) in enumerate(entries.items()):
                token=self.token(name)
                pointer=address+12*index
                bucket=address+0x30000+(token&2047)*4
                oracle.set_integer(pointer,token)
                oracle.set_integer(pointer+4,value)
                oracle.set_integer(pointer+8,oracle.integer(bucket))
                oracle.set_integer(bucket,pointer)
            oracle.set_integer(address+0x32000,len(entries))

    def snapshot(self):
        for address,table in TABLES.items():
            size=self.oracle.integer(address+0x32000)
            if size>16384:raise ValueError('Invalid native map size')
            for index in range(size):
                pointer=address+12*index
                name=self.name(self.oracle.integer(pointer))
                self.state[table][name]=self.oracle.integer(pointer+4)
                if table in ['stock_limits','acquisition_limits']:
                    self.state[table.removesuffix('_limits')+'_registered'][name]=True
        return copy.deepcopy(self.state)


class AvailabilityOracle(Oracle):
    def configure(self,state):
        self.storage=NativeAvailabilityStorage(self,state)
        if not self.handles:
            self.adapters={0x10179af0:lambda:self.storage.diagnostic()}
            self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def query(self,step):
        self.storage.events=[]
        token=self.storage.token(step['key'])
        address={'available':0x10001600,'owned':0x100015d0,'acquired':0x100015b0}[step.get('action','available')]
        value=self.call(address,[token])
        return dict(value=value,state=self.storage.snapshot(),events=copy.deepcopy(self.storage.events))


class ChestCapacityOracle(LifetimeOracle):
    def configure_capacity(self):
        self.configure_lifetime()
        del self.adapters[0x10001600]
        self.adapters[0x10001360]=lambda:self.storage.lookup()
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.hook,begin=0x10001360,end=0x10001360))
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_capacity,begin=0x10001600,end=0x10001600))

    def observe_capacity(self,cpu,address,size,user):
        self.event('reward_available',[self.key(self.arguments(1)[0])])

    def opened_log(self):
        if self.arguments(1)[0]==35:self.storage.diagnostic()
        else:super().opened_log()


def composed_cases(raw,content):
    oracle=ChestCapacityOracle(raw)
    oracle.configure_capacity()
    examples=[]
    for source in [make_case('unknown'),make_case('stock_full',3,100,3,0),
                   make_case('stock_released',3,100,3,1),make_case('lifetime_full',100,3,3,1),
                   make_case('zero_limit',0,0),make_case('unsigned_over_limit',2,100,3,0),
                   make_case('bonus_with_stock',10,20,3,1)]:
        state=source['state']
        reward='Reward_RandomStickerOrGem'
        for table in state.values():
            if '@17' in table:table[reward]=table.pop('@17')
        case=dict(name=source['name'],chests=[chest(phase=1,elapsed=1.,reward=reward)],availability=state,
                  steps=[dict(delta=.1),dict(delta=.1),dict(delta=1.)])
        if source['name']=='bonus_with_stock':case.update(reward_type_a=True,unlocks=['CHEST_BONUS_1'])
        oracle.load(case,content['lifetime_rules'])
        oracle.storage=AvailabilityStorage(oracle,state,oracle.tokens)
        case['states']=[]
        for step in case['steps']:
            oracle.storage.events=[]
            result=oracle.advance(step,content['lifetime_rules'])
            result['availability']=oracle.storage.snapshot()
            result['availability_events']=copy.deepcopy(oracle.storage.events)
            case['states'].append(result)
        examples.append(case)
    return dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],cases=examples,
                native_routines={key:content['native_routines'][key] for key in ['0x10153370','0x101521b0','0x10001480','0x100015b0']},
                adapters=[hex(a) for a in sorted(oracle.adapters)],observation_hooks=['0x101521b0','0x10152ae4','0x10001600'],
                scope='Original chest lifetime composed with original reward capacity. Storage, terrain, influence, presentation, progression and final grant dispatch are adapters; reward redemption remains outside this comparison.')


def make_case(name,stock=None,acquisition=None,acquired=None,spent=None,key=17,steps=None,**extra):
    state=empty()
    id=canonical(key)
    for kind,value in [('stock',stock),('acquisition',acquisition)]:
        if value is not None:
            state[kind+'_registered'][id]=True
            state[kind+'_limits'][id]=value
    for table,value in [('acquired',acquired),('spent',spent)]:
        if value is not None:state[table][id]=value
    for table,values in extra.items():state[table].update(values)
    return dict(name=name,state=state,steps=steps or [dict(key=key),dict(action='owned',key=key),dict(action='acquired',key=key),dict(key=key)])


def cases():
    result=[make_case('unknown'),make_case('zero_limits',0,0),make_case('stock_cap',10,100,4,2),
            make_case('acquisition_cap',100,10,4,2),make_case('spent_frees_stock',10,100,10,7),
            make_case('spent_does_not_free_lifetime',100,10,10,7),make_case('stock_underflow',2,100,10,0),
            make_case('acquisition_underflow',100,2,10,0),make_case('owned_underflow',100,100,2,10),
            make_case('all_max',0xffffffff,0xffffffff,0xffffffff,0xffffffff),
            make_case('numeric_zero',4,8,1,0,key=0),make_case('string_key',10,20,3,1,key='Reward_ChestSticker'),
            make_case('unknown_resets_existing',stock_limits={'@17':0},acquisition_limits={'@17':1}),
            make_case('registered_missing_values',stock_registered={'@17':True},acquisition_registered={'@17':True}),
            make_case('collision_chains',12,20,2,1,stock_registered={'@2065':True,'@4113':True},acquisition_registered={'@2065':True,'@4113':True}),
            make_case('colliding_unregistered',stock_registered={'@2065':True,'@4113':True},acquisition_registered={'@2065':True,'@4113':True}),
            make_case('independent_keys',stock=7,acquisition=20,acquired=2,steps=[dict(key=17),dict(key=18),dict(action='owned',key=19),dict(key=17)]),
            make_case('acquisition_only',acquisition=10,acquired=5,spent=2),make_case('stock_only',stock=10,acquired=5,spent=2)]
    rng=random.Random(0x1600)
    for index in range(48):
        values=[rng.choice([0,1,2,10,0x0fffffff,0x7fffffff,0xfffffffe,0xffffffff,rng.getrandbits(32)]) for _ in range(4)]
        result.append(make_case('unsigned_'+str(index),*values,key=rng.getrandbits(32)))
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default='game/tests/fixtures/source_availability.json')
    args=parser.parse_args()
    content=extract()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    oracle=AvailabilityOracle(raw)
    examples=cases()
    for case in examples:
        oracle.configure(case['state'])
        case['states']=[oracle.query(step) for step in case['steps']]
    result=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],
                native_routines={hex(a):oracle.image.read(a,b-a).hex() for a,b in ROUTINES.items()},
                adapters=[hex(a) for a in oracle.adapters],scope=__doc__.strip(),cases=examples)
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original reward availability:',len(examples),'cases,',sum(len(c['steps']) for c in examples),'queries',flush=True)
    composed=composed_cases(raw,content)
    (ROOT/'game/tests/fixtures/source_chest_reward_capacity.json').write_text(json.dumps(composed,indent=2)+'\n')
    print('Original chest reward capacity:',len(composed['cases']),'cases,',sum(len(c['steps']) for c in composed['cases']),'transitions',flush=True)


if __name__=='__main__':main()
