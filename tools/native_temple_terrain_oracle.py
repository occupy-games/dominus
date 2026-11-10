"""Execute original temple pre-work terrain transitions in a bounded CPU frame.

The actual phase, work conversion, decay, removal flag and audio-handle clearing
instructions run. Type-query, particle and audio services are recorded adapters.
This does not execute obstruction collection, earlier timer updates or removal.
"""
import copy
import json
import random
import struct

from tools.native_scenery_oracle import Oracle,ROOT
from tools.temple_terrain import extract


def f32(value):return struct.unpack('<f',struct.pack('<f',value))[0]


def state(**changes):
    result=dict(phase=5,transition_mode=1,generic_type=123,remove_requested=0,obstruction=1,
                audio_handle=-1,footprint_width=4,progress=30.,required=60.,timer=0.,forced=False)
    result.update(changes)
    for name in ['progress','required','timer']:result[name]=f32(result[name])
    return result


class TempleTerrainOracle(Oracle):
    FIELDS={'phase':0x2fc,'transition_mode':0x3c4,'generic_type':0x30c,'remove_requested':0x230,
            'obstruction':0x2bc,'audio_handle':0x3ec,'footprint_width':0x31c}
    FLOATS={'progress':0x20,'required':0x3c8,'timer':0x24}

    def configure_terrain(self,content):
        self.content=content
        self.configure(b'',b'',b'',[])
        self.adapters={0x1003b550:self.refresh_footprint,0x100400b0:self.settlement,0x10255ad0:self.start_effect,0x10255a70:self.stop_effect,
                       0x102545c0:self.sound,0x1024a6a0:self.audio_lookup,0x1024d580:self.audio_release,
                       0x1024a7a0:self.audio_fade}
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        for kind in content['special_types']:self.set_integer(int(kind['slot'],16),kind['id'])

    def record(self,name,args=()):
        self.events.append([name,list(args),self.integer(self.site+0x2fc),self.float(self.site+0x20),self.float(self.site+0x24)])
    def settlement(self):self.record('is_settlement');self.return_integer(int(self.case.get('is_settlement',False)))
    def refresh_footprint(self):self.record('refresh_footprint');self.return_integer()
    def start_effect(self):
        kind,position,handle,count=self.arguments(4)
        assert position==self.site+0x278 and handle==self.site+0x3dc
        self.record('start_effect',[kind,count]);self.return_integer()
    def stop_effect(self):
        kind,position,handle,count=self.arguments(4)
        assert position==self.site+0x278 and handle==self.site+0x3dc
        self.record('stop_effect',[kind,count]);self.return_integer()
    def sound(self):
        kind,position,zero,priority,flag=self.arguments(5)
        assert position==self.site+0x278
        self.record('sound',[kind,zero,priority,flag]);self.return_integer()
    def audio_lookup(self):self.record('audio_lookup',self.arguments(2));self.return_integer(99)
    def audio_release(self):
        owner,lookup=self.arguments(2)
        assert lookup==99
        self.record('audio_release');self.return_integer()
    def audio_fade(self):
        handle,value=self.arguments(2)
        self.record('audio_fade',[handle,struct.unpack('<f',struct.pack('<I',value))[0]]);self.return_integer()

    def snapshot(self):
        result=copy.deepcopy(self.case['state'])
        for name,offset in self.FIELDS.items():
            result[name]=self.integer(self.site+offset)
            if name in ['obstruction','audio_handle'] and result[name]>=0x80000000:result[name]-=0x100000000
        for name,offset in self.FLOATS.items():result[name]=self.float(self.site+offset)
        return result

    def run_case(self,case):
        self.case=case;self.events=[];self.site=self.POOL
        self.cpu.mem_write(self.site,bytes(0x43c))
        for name,offset in self.FIELDS.items():self.set_integer(self.site+offset,case['state'][name])
        for name,offset in self.FLOATS.items():self.set_float(self.site+offset,case['state'][name])
        self.cpu.mem_write(self.site+0x3f9,bytes([int(case['state']['forced'])]))
        frame=self.STACK+0x80000
        self.set_float(frame+8,case.get('delta',.1))
        for register,value in [(self.regs.UC_X86_REG_ESP,frame-0x200),(self.regs.UC_X86_REG_EBP,frame),
                               (self.regs.UC_X86_REG_ESI,self.site),(self.regs.UC_X86_REG_EBX,0),(self.regs.UC_X86_REG_EDI,5)]:self.cpu.reg_write(register,value)
        self.cpu.mem_write(self.SCRATCH+0x700,b'\xdb\xe3')
        self.cpu.emu_start(self.SCRATCH+0x700,self.SCRATCH+0x702)
        self.cpu.emu_start(0x10140ded,0x101410c8,count=200000)
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=0x101410c8:raise ValueError('Temple terrain instruction budget exhausted')
        return dict(state=self.snapshot(),events=copy.deepcopy(self.events))


def cases(content):
    examples=[]
    kinds=[123,*content['rules']['special_types']]
    for phase in range(9):
        for mode in [0,1,7]:
            for obstruction,forced in [(-1,False),(0,False),(1,False),(0,True)]:
                examples.append(dict(name=f'phase_{phase}_{mode}_{obstruction}_{forced}',state=state(phase=phase,transition_mode=mode,obstruction=obstruction,forced=forced)))
    for kind in kinds:
        limit=content['rules']['special_seconds'] if kind in content['rules']['special_types'] else content['rules']['ordinary_seconds']
        for timer in [0,limit-.125,limit,limit+.125]:
            for settlement in [False,True]:
                for audio in [-1,0,7]:
                    examples.append(dict(name=f'boundary_{kind}_{timer}_{settlement}_{audio}',state=state(phase=8,generic_type=kind,timer=timer,audio_handle=audio),is_settlement=settlement))
        for mode in [0,1]:
            examples.append(dict(name=f'restore_{kind}_{mode}',state=state(phase=8,generic_type=kind,timer=limit*.25,obstruction=0,transition_mode=mode),is_settlement=True))
    rng=random.Random(0x10140ded)
    for index in range(100):
        examples.append(dict(name=f'arithmetic_{index}',delta=f32(rng.random()),is_settlement=bool(index%2),
                             state=state(phase=rng.choice([5,6,8]),generic_type=rng.choice(kinds),footprint_width=rng.choice([1,2,4,16,300,65535]),
                                         obstruction=rng.choice([-2,0,1,3,20,500]),progress=f32(rng.random()*100),required=f32(.1+rng.random()*100),
                                         timer=f32(rng.random()*60))))
    return examples


def main():
    content=extract();oracle=TempleTerrainOracle((ROOT/'data/godus2_4/godus.s86').read_bytes());oracle.configure_terrain(content)
    examples=cases(content)
    for case in examples:
        try:case['expected']=oracle.run_case(case)
        except Exception as error:raise ValueError('Original terrain case '+case['name']+' at '+hex(oracle.cpu.reg_read(oracle.regs.UC_X86_REG_EIP))) from error
    sequences=[]
    for kind in [123,content['rules']['special_types'][0]]:
        sequence=dict(initial=state(generic_type=kind,footprint_width=2),steps=[])
        current=sequence['initial']
        for index in range(16):
            case=dict(state=copy.deepcopy(current),delta=f32(.25),is_settlement=True)
            case['state']['obstruction']=0 if 4<=index<8 else 2
            result=oracle.run_case(case);current=result['state']
            sequence['steps'].append(dict(obstruction=case['state']['obstruction'],expected=result))
        sequences.append(sequence)
    fixture=dict(executable_sha256=content['executable_sha256'],cases=examples,sequences=sequences,
                 native_routines=content['native_routines'],adapters=[hex(a) for a in sorted(oracle.adapters)],scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_temple_terrain.json').write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    print('Original temple terrain:',len(examples),'cases,',sum(len(s['steps']) for s in sequences),'sequence steps',flush=True)


if __name__=='__main__':main()
