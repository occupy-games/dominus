"""Execute original temple upgrade-mask refresh, popcount and unlock lookup.

Source table loading and its parsed family labels are injected. The original
refresh and original unlock hash-table lookup execute; spatial invalidation is
an explicit recorded service. No executable entrypoint or device is started.
"""
import copy
import json

from tools.native_scenery_oracle import Oracle,ROOT
from tools.temple_modifiers import extract
from tools.reward_dispatch import key


def state(**changes):
    result=dict(generic_type=key('Monument_Speed'),x=10.25,z=-12.5,follower_modifiers=[0,0],house_modifiers=[0,0])
    result.update(changes);return result


def load_tables(oracle,records,unlocked):
    oracle.cpu.mem_write(0x10f1e350,bytes(128*4));oracle.cpu.mem_write(0x10f1e560,bytes(128*0x1c))
    for index,record in enumerate(records):
        oracle.set_integer(0x10f1e350+index*4,record['family'])
        oracle.set_integer(0x10f1e560+index*0x1c,record['type']);oracle.set_integer(0x10f1e564+index*0x1c,record['unlock'])
    oracle.cpu.mem_write(0x10cd9760,bytes(1024*4))
    for index,identity in enumerate(unlocked):
        bucket=0x10cd9760+(identity&1023)*4;pointer=oracle.GRIDS+0x200000+index*8
        oracle.set_integer(pointer,identity);oracle.set_integer(pointer+4,oracle.integer(bucket));oracle.set_integer(bucket,pointer)


def write_masks(oracle,current):
    for field,start in [('follower_modifiers',0x42c),('house_modifiers',0x424)]:
        for index,word in enumerate(current[field]):oracle.set_integer(oracle.site+start+4*index,word)


def read_masks(oracle):
    return {field:[oracle.integer(oracle.site+start+4*index) for index in range(2)] for field,start in [('follower_modifiers',0x42c),('house_modifiers',0x424)]}


class ModifiersOracle(Oracle):
    def configure_modifiers(self):
        self.configure(b'',b'',b'',[]);self.adapters={0x1012c970:self.invalidate}
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.observe_unlock,begin=0x1015c130,end=0x1015c130))

    def record(self,name,args):self.events.append([name,list(args),read_masks(self)])

    def observe_unlock(self,cpu,address,size,user):self.record('unlocked',self.arguments(1))

    def invalidate(self):
        values=[v-0x100000000 if v>=0x80000000 else v for v in self.arguments(2)]
        self.record('invalidate_modifiers_at',values);self.return_integer()

    def run_case(self,case):
        self.case=case;self.site=self.POOL;self.events=[]
        self.cpu.mem_write(self.site,bytes(0x43c));current=case['state']
        self.set_integer(self.site+0x30c,current['generic_type'])
        for field,offset in [('x',0x278),('z',0x27c)]:self.set_float(self.site+offset,current[field])
        write_masks(self,current);load_tables(self,case['records'],case['unlocked'])
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.site)
        self.call(0x1013dd90,limit=5000000)
        result=copy.deepcopy(current);result.update(read_masks(self))
        return dict(state=result,events=copy.deepcopy(self.events))


def cases(records):
    examples=[]
    ids=list(dict.fromkeys(r['unlock'] for r in records))
    for kind in dict.fromkeys(r['type'] for r in records):
        for flags in range(1<<len(ids)):
            for old in [[0,0],[1,0],[0,0x80000000]]:
                examples.append(dict(name=f'source_{kind}_{flags}_{old[1]}_{old[0]}',state=state(generic_type=kind,follower_modifiers=old),
                                     records=records,unlocked=[identity for index,identity in enumerate(ids) if flags&(1<<index)]))
    synthetic=[dict(type=123 if index%2==0 else 456,unlock=1000+index,family=family) for family in [0,1] for index in range(64)]
    for index in [0,1,30,31,32,33,62,63]:
        for kind in [123,456]:
            examples.append(dict(name=f'bit_{index}_{kind}',state=state(generic_type=kind),records=synthetic,unlocked=[1000+index]))
    examples.append(dict(name='different_type_clears_old_masks',state=state(generic_type=777,follower_modifiers=[0xffffffff,0xffffffff],house_modifiers=[1,1]),records=records,unlocked=ids))
    examples.append(dict(name='empty_table_clears_old_masks',state=state(follower_modifiers=[1,0]),records=[],unlocked=[]))
    return examples


def main():
    content=extract();oracle=ModifiersOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_modifiers()
    examples=cases(content['records'])
    for case in examples:case['expected']=oracle.run_case(case)
    sequences=[]
    for kind in dict.fromkeys(r['type'] for r in content['records']):
        sequence=dict(initial=state(generic_type=kind),steps=[]);current=copy.deepcopy(sequence['initial'])
        for index in range(16):
            step=dict(records=content['records'],unlocked=list(dict.fromkeys(r['unlock'] for r in content['records'])) if index%4 in [1,2] else [])
            expected=oracle.run_case(dict(step,state=current));current=copy.deepcopy(expected['state'])
            sequence['steps'].append(dict(step,expected=expected))
        sequences.append(sequence)
    fixture=dict(executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],cases=examples,sequences=sequences,
                 native_routines=content['native_routines'],adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_temple_modifiers.json').write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    print('Original temple modifiers:',len(examples),'cases,',sum(len(s['steps']) for s in sequences),'steps',flush=True)


if __name__=='__main__':main()
