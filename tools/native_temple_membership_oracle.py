"""Execute original temple containment and timed affiliation instructions.

The original circle/sphere predicates, active-list traversal, owner writes and
deadline arithmetic execute. Type-radius lookup, modifier refresh, clock and RNG
are explicit in-memory services. No original executable entrypoint is launched.
"""
import copy
import json
import random
import struct

from tools.native_scenery_oracle import Oracle,ROOT
from tools.native_temple_terrain_oracle import f32
from tools.temple_membership import extract


def site(handle=3,**changes):
    result=dict(handle=handle,settlement_id=-1,is_settlement=False,x=10.,z=12.,height=6.,radius=12.)
    result.update(changes)
    for key in ['x','z','height','radius']:result[key]=f32(result[key])
    return result


def state(**changes):
    result=site();result['affiliation_due']=0.;result.update(changes)
    result['affiliation_due']=f32(result['affiliation_due'])
    return result


class MembershipOracle(Oracle):
    def configure_membership(self,content):
        self.content=content;self.configure(b'',b'',b'',[])
        self.adapters={0x100400b0:self.settlement,0x1003fee0:self.lookup,
                       0x1013dd90:self.modifiers,0x10179810:self.clock,0x1035f7f0:self.random_word}
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def record(self,name,args=()):
        owner=self.integer(self.site+0x2b4);owner=owner-0x100000000 if owner>=0x80000000 else owner
        self.events.append([name,list(args),owner,self.float(self.site+0x378)])

    def settlement(self):
        pointer=self.cpu.reg_read(self.regs.UC_X86_REG_ECX)-0x23c
        self.return_integer(int(self.records[pointer]['is_settlement']))

    def lookup(self):
        pointer=self.arguments(1)[0]-0x30c
        row=self.SCRATCH+0x8000
        self.set_float(row+0x10,self.records[pointer]['radius'])
        self.return_integer(row,pop=4)

    def modifiers(self):
        self.record('refresh_modifiers')
        if 'modifiers_due' in self.case:self.set_float(self.site+0x378,self.case['modifiers_due'])
        self.return_integer()

    def clock(self):
        self.record('clock',self.arguments(1))
        values=self.case.get('times',[0.])
        value=values[min(self.clock_calls,len(values)-1)];self.clock_calls+=1
        self.return_float(value)

    def random_word(self):
        self.record('random_word');self.random_calls+=1
        self.return_integer(self.case.get('word',0))

    def write_site(self,pointer,data):
        self.records[pointer]=copy.deepcopy(data)
        self.cpu.mem_write(pointer,bytes(0x43c))
        self.set_integer(pointer+0x2b4,data.get('settlement_id',-1))
        for field,offset in [('x',0x278),('z',0x27c),('height',0x280)]:self.set_float(pointer+offset,data[field])

    def prepare(self,current,owners,sites):
        self.records={};self.events=[];self.clock_calls=0;self.random_calls=0
        self.site=self.POOL+current['handle']*0x43c
        self.set_integer(0x10f29ba0,self.POOL)
        self.cpu.mem_write(0x10f29baa,struct.pack('<H',sites[0]['handle'] if sites else 0xffff))
        for index,data in enumerate(sites):
            pointer=self.POOL+data['handle']*0x43c;self.write_site(pointer,data)
            self.cpu.mem_write(pointer,struct.pack('<H',sites[index+1]['handle'] if index+1<len(sites) else 0xffff))
        self.write_site(self.site,current)
        for index,(identity,data) in enumerate(owners.items()):
            pointer=self.GRIDS+0x20000+index*0x43c
            if data is None:self.set_integer(0x10bc9878+int(identity)*384,0)
            else:
                self.write_site(pointer,data);self.set_integer(0x10bc9878+int(identity)*384,pointer)

    def run_contains(self,case):
        self.case=case;self.prepare(case['site'],case.get('owners',{}),[])
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.site)
        words=[struct.unpack('<I',struct.pack('<f',v))[0] for v in case['point']]
        return bool(self.call(0x1013f080,words,limit=500000)&255)

    def run_membership(self,case):
        self.case=case;current=case['state'];self.prepare(current,case.get('owners',{}),case.get('sites',[]))
        self.set_float(self.site+0x378,current['affiliation_due'])
        frame=self.STACK+0x80000
        for reg,value in [(self.regs.UC_X86_REG_ESP,frame-0x200),(self.regs.UC_X86_REG_EBP,frame),
                          (self.regs.UC_X86_REG_ESI,self.site),(self.regs.UC_X86_REG_EBX,0)]:self.cpu.reg_write(reg,value)
        self.cpu.mem_write(self.SCRATCH+0x700,b'\xdb\xe3');self.cpu.emu_start(self.SCRATCH+0x700,self.SCRATCH+0x702)
        self.cpu.emu_start(0x10140c0f,0x10140d1e,count=5000000)
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=0x10140d1e:raise ValueError('Membership instruction budget exhausted')
        result=copy.deepcopy(current);owner=self.integer(self.site+0x2b4)
        result['settlement_id']=owner-0x100000000 if owner>=0x80000000 else owner
        result['affiliation_due']=self.float(self.site+0x378)
        return dict(state=result,events=copy.deepcopy(self.events),clock_calls=self.clock_calls,random_calls=self.random_calls,refreshed=bool(self.random_calls))


def geometry_cases():
    result=[]
    owner=site(5,settlement_id=2,is_settlement=True)
    for settlement in [False,True]:
        for inherited in [False,True]:
            for radius in [0.,-12.,12.]:
                current=site(is_settlement=settlement,settlement_id=2 if inherited else -1,radius=radius)
                owners={'2':dict(owner,radius=radius)}
                for x,z,height in [(10,12,6),(22,12,6),(21.999998,12,6),(22.000002,12,6),(10,12,18),(10,12,100),(15,15,12)]:
                    result.append(dict(name=f'boundary_{settlement}_{inherited}_{radius}_{x}_{z}_{height}',site=current,owners=owners,point=[f32(x),f32(z),f32(height)]))
    result.append(dict(name='missing_owner',site=site(settlement_id=9),owners={'9':None},point=[10.,12.,6.]))
    for radius in [.1,1.1,12.3]:
        for inherited in [False,True]:
            current=site(settlement_id=2 if inherited else -1,x=0,z=0,height=0,radius=radius)
            result.append(dict(name=f'rounded_radius_{radius}_{inherited}',site=current,owners={'2':dict(owner,x=0,z=0,height=0,radius=f32(radius))},point=[f32(radius),0.,0.]))
    rng=random.Random(0x1013f080)
    for index in range(100):
        attached=bool(index%2);settlement=bool(index%3==0)
        current=site(is_settlement=settlement,settlement_id=2 if attached else -1,x=10+rng.random(),z=12+rng.random(),height=6+rng.random(),radius=3+rng.random()*12)
        result.append(dict(name=f'arithmetic_{index}',site=current,owners={'2':dict(owner,radius=f32(3+rng.random()*12))},point=[f32(8+rng.random()*20),f32(8+rng.random()*20),f32(4+rng.random()*20)]))
    return result


def membership_cases():
    first=site(4,settlement_id=2,is_settlement=True)
    second=site(7,settlement_id=5,is_settlement=True,x=11)
    other=site(8,is_settlement=False)
    distant=site(9,settlement_id=6,is_settlement=True,x=200)
    examples=[]
    for owner in [-1,2]:
        for settlement in [False,True]:
            for due in [-1.,0.,1.]:
                for word in [0,16383,32767]:
                    examples.append(dict(name=f'gate_{owner}_{settlement}_{due}_{word}',state=state(settlement_id=owner,is_settlement=settlement,affiliation_due=due),sites=[first,other,distant,second],times=[0.],word=word))
    for ordered in [[first,second],[second,first],[other,distant],[]]:
        examples.append(dict(name='order_'+','.join(str(s['handle']) for s in ordered),state=state(),sites=ordered,times=[10.,11.],word=32767))
    examples.append(dict(name='modifier_delays_refresh',state=state(),sites=[first],times=[0.],modifiers_due=2.))
    rng=random.Random(0x10140c0f)
    for index in range(60):
        now=f32(rng.choice([0.,100.,10000000.])+rng.random()*10)
        examples.append(dict(name=f'clock_{index}',state=state(affiliation_due=f32(now-1)),sites=[first],times=[now,f32(now+rng.random())],word=rng.randrange(32768)))
    return examples


def main():
    content=extract();oracle=MembershipOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_membership(content)
    geometry=geometry_cases();examples=membership_cases()
    for case in geometry:
        try:case['expected']=oracle.run_contains(case)
        except Exception as error:raise ValueError('Native geometry '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    for case in examples:
        try:case['expected']=oracle.run_membership(case)
        except Exception as error:raise ValueError('Native affiliation '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    sequences=[]
    for initial_owner in [-1,2]:
        sequence=dict(initial=state(settlement_id=initial_owner),steps=[]);current=copy.deepcopy(sequence['initial'])
        for tick in range(32):
            step=dict(sites=[site(4,settlement_id=2,is_settlement=True)],times=[float(tick)],word=16383)
            expected=oracle.run_membership(dict(step,state=current));current=copy.deepcopy(expected['state'])
            sequence['steps'].append(dict(step,expected=expected))
        sequences.append(sequence)
    fixture=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],geometry=geometry,cases=examples,sequences=sequences,
                 native_routines=content['native_routines'],adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_temple_membership.json').write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    print('Original temple membership:',len(geometry),'geometry cases,',len(examples),'affiliation cases,',sum(len(s['steps']) for s in sequences),'steps',flush=True)


if __name__=='__main__':main()
