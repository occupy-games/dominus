"""Compare original effect parsing, mask collection and actual stat getters.

The original parser resolves injected table/column descriptors and executes its
prefix/number storage. Actor queries execute actual temple containment, mask OR,
race/job row copying and ordered application. House queries execute the actual
class filters and shrine modifier loop, with unrelated global modifiers empty.
Resolved base rows, source table loading, string services and center queries are
explicit adapters. No executable entrypoint or device is run.
"""
import copy
import json
import random
import struct

from tools.native_scenery_oracle import ROOT
from tools.native_temple_membership_oracle import MembershipOracle,site
from tools.native_temple_modifiers_oracle import write_masks,load_tables
from tools.temple_effects import extract
from tools.reward_dispatch import key
from tools.native_temple_terrain_oracle import f32


def bits(value):return struct.unpack('<I',struct.pack('<f',value))[0]


def effect_site(handle,**changes):
    current=site(handle);current.update(generic_type=123,follower_modifiers=[0,0],house_modifiers=[0,0]);current.update(changes)
    return current


class EffectsOracle(MembershipOracle):
    ACTOR=0x34060000
    BODY=0x34061000
    BASE=0x34070000

    def configure_effects(self,content):
        self.configure_membership(content);self.effect_content=content
        self.owner_ids=set()
        del self.adapters[0x1013dd90]
        self.adapters.update({0x1035f830:lambda:self.return_integer(),0x1003bbc0:self.center,
                              0x1012c970:lambda:self.return_integer(),
                              0x100b6750:lambda:self.return_integer(self.BASE),
                              0x101b51e0:self.construct_name,0x101b5260:self.hash_name,
                              0x1024b160:self.split,0x10170c40:self.table_lookup,
                              0x10170500:self.column_lookup,0x10364270:self.number})
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def string(self,pointer):return bytes(self.cpu.mem_read(pointer,200)).split(b'\0')[0].decode()

    def prepare(self,current,owners,sites):
        for identity in self.owner_ids:self.set_integer(0x10bc9878+identity*384,0)
        self.owner_ids={int(identity) for identity in owners}
        super().prepare(current,owners,sites)

    def center(self):
        target=self.arguments(1)[0]
        for index,value in enumerate(self.case['point']):self.set_float(target+4*index,value)
        self.return_integer(target,pop=4)

    def construct_name(self):self.name=self.string(self.arguments(1)[0]);self.return_integer(pop=4)

    def hash_name(self):self.return_integer(key(self.name))

    def split(self):
        text,separator,target=self.arguments(3)
        assert self.string(separator)==','
        tokens=self.string(text).split(',');array=self.SCRATCH+0x2000;cursor=self.SCRATCH+0x2400
        for index,token in enumerate(tokens):
            self.set_integer(array+4*index,cursor);self.cpu.mem_write(cursor,token.encode()+b'\0');cursor+=len(token.encode())+1
        self.set_integer(target,array);self.return_integer(len(tokens))

    def table_lookup(self):
        name=self.string(self.arguments(1)[0]);names=list(self.effect_content['row_words'])
        self.return_integer(names.index(name) if name in names else -1)

    def column_lookup(self):
        table=self.cpu.reg_read(self.regs.UC_X86_REG_ECX);names=list(self.effect_content['row_words'])
        name=names[(table-(self.GRIDS+0x80000))//0x100]
        column=self.string(self.arguments(1)[0])
        binding=self.effect_content['bindings'][name][column]
        self.set_integer(table+0x18,table+0x40);self.set_integer(table+0x28,table+0x80)
        self.set_integer(table+0x44,table+0x80+4*binding['index']);self.return_integer(0,pop=4)

    def number(self):self.return_float(float(self.string(self.arguments(1)[0])))

    def run_parse(self,text):
        for index,_ in enumerate(self.effect_content['row_words']):self.set_integer(0x10d5a4e0+index*4,self.GRIDS+0x80000+index*0x100)
        target=self.GRIDS+0xb0000;self.cpu.mem_write(target,bytes(0x24));self.cpu.mem_write(self.SCRATCH+0x1000,text.encode()+b'\0')
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,target)
        self.call(0x10171610,[self.SCRATCH+0x1000],limit=500000)
        return dict(index=self.integer(target+0x18),value=self.float(target+0x1c),operation=self.integer(target+0x20))

    def load_effects(self,records):
        self.cpu.mem_write(0x10f1f95c,bytes(0x1200));self.cpu.mem_write(0x10f20d9c,bytes(16))
        counts=[0,0]
        for record in records:
            family=record['family'];index=counts[family];counts[family]+=1
            pointer=(0x10f1f95c if family==0 else 0x10f2025c)+index*0x24
            self.set_integer(pointer+0x18,record['index']);self.set_float(pointer+0x1c,record['value']);self.set_integer(pointer+0x20,record['operation'])
            for flag,offset in [('abode',0),('monastery',4),('farm',8),('mine',12)]:self.set_integer(pointer+offset,record[flag])
            if family==0:
                mask=0x10f20d9c if record['table']=='race' else 0x10f20da4
                word=mask+4*(index//32);self.set_integer(word,self.integer(word)|(1<<(index%32)))

    def prepare_sites(self,sites,owners):
        self.prepare(site(500),owners,sites);original=self.site
        for data in sites:
            self.site=self.POOL+data['handle']*0x43c;write_masks(self,data)
            self.set_integer(self.site+0x30c,data['generic_type'])
        if 'unlocked' in self.case:
            load_tables(self,self.case['records'],self.case['unlocked'])
            for data in sites:
                self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.POOL+data['handle']*0x43c)
                self.call(0x1013dd90,limit=5000000)
        self.site=original

    def run_area(self,case):
        self.case=case;self.prepare(case['site'],case.get('owners',{}),[])
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.site)
        radius=self.SCRATCH+0xc000;center=radius+4
        ok=bool(self.call(0x1013efa0,[radius,center],limit=500000)&255)
        return dict(center=[self.float(center+4*i) for i in range(3)],radius=self.float(radius)) if ok else {}

    def run_stat(self,case):
        self.case=case;self.prepare_sites(case['sites'],case.get('owners',{}));self.load_effects(case['records'])
        self.cpu.mem_write(self.ACTOR,bytes(0x2d8));self.cpu.mem_write(self.BODY,bytes(0x100))
        self.cpu.mem_write(self.BASE,struct.pack('<'+'I'*len(case['base']),*case['base']))
        if case['table']!='House Values':
            self.set_integer(self.ACTOR+0x18,self.BODY if case['point'] is not None else 0)
            if case['point'] is not None:
                for index,value in enumerate(case['point']):self.set_float(self.BODY+0x70+4*index,value)
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.ACTOR);self.call(0x100340d0,limit=5000000)
            mask=[self.integer(self.ACTOR+0x40+4*i) for i in range(2)]
            for i,word in enumerate(case.get('extra_mask',[0,0])):self.set_integer(self.ACTOR+0x48+4*i,word)
            self.set_integer(0x10fb77bc if case['table']=='race' else 0x10fb8b00,self.BASE)
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.ACTOR)
            output=self.SCRATCH+0xc000
            self.call(0x100342a0 if case['table']=='race' else 0x100343b0,[output],limit=5000000)
        else:
            parameters=case['parameters'];self.set_integer(self.ACTOR+0x30,int(parameters['special']));self.set_integer(self.ACTOR+0x20,parameters['kind'])
            self.collect_house()
            mask=[self.integer(self.ACTOR+0xc+4*i) for i in range(2)]
            self.cpu.mem_write(0x10f1f75c,bytes(0x200));self.cpu.mem_write(0x10d9b5f8,b'\0')
            self.set_integer(self.ACTOR+0x88,1234)
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.ACTOR);output=self.call(0x100b7580,limit=5000000)
        values=list(struct.unpack('<'+'I'*len(case['base']),self.cpu.mem_read(output,4*len(case['base']))))
        return dict(mask=mask,values=values)

    def collect_house(self):
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.ACTOR);self.call(0x100b6d60,limit=5000000)


def source_sites():
    return [effect_site(4,generic_type=key('Monument_Speed'),follower_modifiers=[3,0]),
            effect_site(5,generic_type=key('Monument_Cooking'),follower_modifiers=[60,0]),
            effect_site(7,generic_type=key('Monument_Family'),house_modifiers=[3,0])]


def base_words(table):
    count={'race':41,'jobs':16,'House Values':76}[table];result=[bits(1.)]*count
    if table=='race':result[2]=bits(.9);result[21]=bits(.005)
    elif table=='jobs':result[10]=bits(.0025)
    else:result[16]=bits(3.);result[10]=key('AbodeType_1_Rank_1')
    return result


def cases(content):
    examples=[];records=content['records']
    points=[[10.,12.,6.],[22.,12.,6.],[22.000002,12.,6.],[10.,12.,100.],None]
    for table in ['race','jobs']:
        for i,point in enumerate(points):
            for extra in [[0,0],[63,0],[0,0xffffffff]]:
                examples.append(dict(name=f'point_{table}_{i}_{extra[0]}_{extra[1]}',table=table,point=point,base=base_words(table),sites=source_sites(),extra_mask=extra,records=records))
    for kind in [0,1,2,3]:
        for special in [False,True]:
            for monastery in [False,True]:
                base=base_words('House Values');base[10]=content['monastery_types'][0]['id'] if monastery else key('AbodeType_1_Rank_1')
                examples.append(dict(name=f'house_{kind}_{special}_{monastery}',table='House Values',point=[10.,12.,6.],base=base,sites=source_sites(),records=records,
                                     parameters=dict(special=special,kind=kind,model_type=base[10])))
    for missing in [False,True]:
        for x,height in [(10.,6.),(22.,6.),(21.999998,6.),(10.,18.)]:
            for table in ['race','jobs','House Values']:
                sites=source_sites()
                for current in sites:current['settlement_id']=2
                examples.append(dict(name=f'inherited_{missing}_{x}_{height}_{table}',table=table,point=[x,12.,height],base=base_words(table),sites=sites,
                                     owners={} if missing else {'2':site(9,is_settlement=True,settlement_id=2)},records=records,
                                     parameters=dict(special=False,kind=0,model_type=key('AbodeType_1_Rank_1'))))
    rng=random.Random(0x100342a0)
    for index in range(64):
        table=['race','jobs','House Values'][index%3];base=[bits(rng.random()*10) for _ in range(content['row_words'][table])]
        if table=='House Values':base[10]=key('AbodeType_1_Rank_1')
        sites=source_sites()
        for current in sites:
            current['follower_modifiers']=[rng.randrange(64),0];current['house_modifiers']=[rng.randrange(4),0]
        examples.append(dict(name=f'arithmetic_{index}',table=table,point=[f32(8+rng.random()*8),f32(8+rng.random()*8),f32(4+rng.random()*4)],base=base,sites=sites,records=records,
                             extra_mask=[rng.randrange(64),0],parameters=dict(special=False,kind=0,model_type=key('AbodeType_1_Rank_1'))))
    # Source operations at both word boundaries and unknown-mode no-op.
    synthetic=[dict(records[0],index=2,operation=i%3,value=f32(.1+i*.03),table='race') for i in range(64)]
    for index in [0,30,31,32,33,62,63]:
        for table in ['race','jobs']:
            mask=[0,0];mask[index//32]=1<<(index%32)
            examples.append(dict(name=f'bit_{table}_{index}',table=table,point=None,base=base_words(table),sites=[],extra_mask=mask,records=synthetic))
    unlocks=list(dict.fromkeys(r['unlock'] for r in records))
    for flags in range(1<<len(unlocks)):
        for table in ['race','jobs','House Values']:
            sites=source_sites()
            for current in sites:current.update(follower_modifiers=[0xffffffff,0xffffffff],house_modifiers=[0xffffffff,0xffffffff])
            examples.append(dict(name=f'refresh_{table}_{flags}',table=table,point=[10.,12.,6.],base=base_words(table),sites=sites,records=records,
                                 unlocked=[identity for index,identity in enumerate(unlocks) if flags&(1<<index)],
                                 parameters=dict(special=False,kind=0,model_type=key('AbodeType_1_Rank_1'))))
    for table in ['race','House Values']:
        sites=source_sites();sites.append(dict(copy.deepcopy(sites[0 if table=='race' else 2]),handle=8))
        examples.append(dict(name='overlap_'+table,table=table,point=[10.,12.,6.],base=base_words(table),sites=sites,records=records,
                             parameters=dict(special=False,kind=0,model_type=key('AbodeType_1_Rank_1'))))
    for monastery in content['monastery_types'][1:]:
        base=base_words('House Values');base[10]=monastery['id']
        examples.append(dict(name='monastery_'+monastery['name'],table='House Values',point=[10.,12.,6.],base=base,sites=source_sites(),records=records,
                             parameters=dict(special=False,kind=0,model_type=monastery['id'])))
    return examples


def main():
    content=extract();oracle=EffectsOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_effects(content)
    parsed=[]
    for record in content['records']:
        parsed.append(dict(effect=record['effect'],expected=oracle.run_parse(record['effect'])))
    for prefix in ['x','m','+','p','-']:
        text='table, race, RouteSpeed, '+prefix+'0.125';parsed.append(dict(effect=text,expected=oracle.run_parse(text)))
    areas=[]
    for attached in [False,True]:
        for settlement in [False,True]:
            for missing in [False,True]:
                case=dict(site=site(settlement_id=2 if attached else -1,is_settlement=settlement),owners={} if missing else {'2':site(9,x=100.,radius=5.)})
                case['expected']=oracle.run_area(case);areas.append(case)
    examples=cases(content)
    for case in examples:
        try:case['expected']=oracle.run_stat(case)
        except Exception as error:raise ValueError('Original shrine stats '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    sequences=[]
    for table in ['race','jobs','House Values']:
        sequence=dict(table=table,base=base_words(table),steps=[])
        for index in range(16):
            sites=source_sites()
            if index%4 in [0,3]:
                for current in sites:current['follower_modifiers']=[0,0];current['house_modifiers']=[0,0]
            step=dict(table=table,point=[10.+index,12.,6.],base=sequence['base'],sites=sites,records=content['records'],
                      parameters=dict(special=False,kind=0,model_type=key('AbodeType_1_Rank_1')))
            step['expected']=oracle.run_stat(step);sequence['steps'].append(step)
        sequences.append(sequence)
    fixture=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],parsed=parsed,areas=areas,cases=examples,sequences=sequences,
                 native_routines=content['native_routines'],adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_temple_effects.json').write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    print('Original shrine effects:',len(parsed),'parses,',len(areas),'areas,',len(examples),'stat cases,',sum(len(s['steps']) for s in sequences),'steps',flush=True)


if __name__=='__main__':main()
