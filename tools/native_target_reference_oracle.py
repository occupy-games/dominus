"""Observe native house/plot target assignment, clearing and worker bookkeeping.

Reference validation/copy, native counters, home/settlement conditions and local
profession side effects execute. Job skill is an explicit supplied input; only
its evaluator and invalid-reference diagnostics are adapters. Full follower
decisions, movement, other reference kinds and settlement lifetime are separate.
"""
import argparse
import hashlib
import json
import struct

from tools.native_scenery_oracle import Oracle, ROOT


class TargetOracle(Oracle):
    HOUSES=0x31000000
    FOLLOWER=0x31800000
    HOUSE_COUNT=4
    PLOT_COUNT=4

    def configure_target(self,case):
        for handle in self.handles:self.cpu.hook_del(handle)
        self.case=case
        self.cpu.mem_write(self.HOUSES,bytes(self.HOUSE_COUNT*0x2d8))
        self.cpu.mem_write(self.POOL,bytes(self.PLOT_COUNT*0x74))
        self.cpu.mem_write(self.FOLLOWER,bytes(0x98))
        self.set_integer(0x10fcd474,self.HOUSES)
        self.set_integer(0x10f8f8d8,self.POOL)
        for base,size,header in [(0x10f928e8,0xc004,0x10fcd474),(0x10f8f8e4,0x3004,0x10f8f8d8)]:
            self.cpu.mem_write(base,bytes(size))
            self.set_integer(base,header)
        self.cpu.mem_write(0x10bc9850,bytes(40*0x180))
        self.set_integer(0x10d9b670,case.get('local_owner',0))
        self.houses=case.get('houses',[dict(identity=0x01000001)])
        self.plots=case.get('plots',[dict(x=158.,z=120.,size=4)])
        for i,house in enumerate(self.houses):
            pointer=self.HOUSES+i*0x2d8
            self.set_integer(pointer+0x88,house.get('identity',0x01000001+i))
            self.set_integer(pointer+0xec,house.get('settlement_index',-1))
            self.set_integer(pointer+0x20,house.get('profession',0))
        for i,plot in enumerate(self.plots):
            pointer=self.POOL+i*0x74
            self.set_integer(pointer+4,plot['size'])
            self.set_float(pointer+8,plot['x'])
            self.set_float(pointer+12,plot['z'])
            self.set_integer(pointer+0x4c,int(plot.get('claimed',False)))
        self.set_integer(self.FOLLOWER+0xc,self.house_pointer(case.get('home',-1)))
        self.set_integer(self.FOLLOWER+0x38,case.get('settlement_index',-1))
        self.set_integer(self.FOLLOWER+0x3c,case.get('profession',0))
        self.set_integer(self.FOLLOWER+0x10,case.get('owner',0)<<29)
        for kind,base,capacity in [('houses',0x10f928e8,4096),('plots',0x10f8f8e4,1024)]:
            for key,counts in case.get('counters',{}).get(kind,{}).items():
                index=int(key)
                self.set_integer(base+4+index*4,counts[0])
                self.set_integer(base+4+capacity*4+index*4,counts[1])
                self.set_float(base+4+capacity*8+index*4,counts[2])
        self.skill_calls=0
        self.adapters={0x10034650:self.skill,0x10354450:lambda:self.return_integer()}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.FOLLOWER+0x1c)
        self.call(0x1016ad70)
        if 'initial_target' in case:
            self.cpu.mem_write(self.FOLLOWER+0x1c,struct.pack('<5I',*self.reference(case['initial_target'])))

    def house_pointer(self,index):return self.HOUSES+index*0x2d8 if index>=0 else 0

    def skill(self):
        self.skill_calls+=1
        self.return_float(self.case['skills'][self.skill_calls-1] if 'skills' in self.case else self.case.get('skill',1.))

    def reference(self,spec):
        kind=spec.get('kind',1)
        index=spec.get('entity',0)
        pointer=(self.HOUSES+index*0x2d8 if kind==1 else self.POOL+index*0x74) if index>=0 else 0
        identity=spec.get('identity',self.houses[index].get('identity',0x01000001+index) if kind==1 and index>=0 else kind<<24)
        position=spec.get('position',[-1.,-1.] if kind==1 else [self.plots[index]['x']+self.plots[index]['size']*.5,self.plots[index]['z']+self.plots[index]['size']*.5])
        return [identity,pointer,*struct.unpack('<2I',struct.pack('<2f',*position)),int(spec.get('flag',True))]

    def snapshot(self):
        identity,pointer,x,z,flag=struct.unpack('<5I',self.cpu.mem_read(self.FOLLOWER+0x1c,20))
        kind=(identity>>24)&31
        entity=(pointer-self.HOUSES)//0x2d8 if kind==1 and pointer else (pointer-self.POOL)//0x74 if kind==7 and pointer else -1
        counter={}
        for name,base,capacity,count in [('houses',0x10f928e8,4096,self.HOUSE_COUNT),('plots',0x10f8f8e4,1024,self.PLOT_COUNT)]:
            rows={}
            for i in range(count):
                values=[self.integer(base+4+i*4),self.integer(base+4+capacity*4+i*4),self.float(base+4+capacity*8+i*4)]
                if any(values):rows[str(i)]=values
            counter[name]=rows
        counter['settlements']={str(i):[self.integer(0x10bc9850+i*0x180+0x110),self.integer(0x10bc9850+i*0x180+0x114)]
                                for i in range(40) if self.integer(0x10bc9850+i*0x180+0x110) or self.integer(0x10bc9850+i*0x180+0x114)}
        home=self.integer(self.FOLLOWER+0xc)
        settlement=self.integer(self.FOLLOWER+0x38)
        return dict(target=dict(identity=identity,entity=entity,position=list(struct.unpack('<2f',struct.pack('<2I',x,z))),flag=bool(flag&255)),
                    home=(home-self.HOUSES)//0x2d8 if home else -1,settlement_index=-1 if settlement==0xffffffff else settlement,
                    house_professions=[self.integer(self.HOUSES+i*0x2d8+0x20) for i in range(len(self.houses))],
                    plot_claimed=[bool(self.integer(self.POOL+i*0x74+0x4c)) for i in range(len(self.plots))],
                    counters=counter,skill_calls=self.skill_calls)

    def step(self,step):
        if self.case.get('no_actor',False):
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.FOLLOWER+0x1c)
            if step.get('type','assign')=='clear':self.call(0x100caeb0,[0])
            else:self.call(0x100caf60,[0,*self.reference(step),step.get('action',250)])
        else:
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX,self.FOLLOWER)
            if step.get('type','assign')=='clear':self.call(0x10033cd0)
            else:self.call(0x10033d20,[*self.reference(step),step.get('action',250)])
        return self.snapshot()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_target_references.json'))
    args=parser.parse_args()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    oracle=TargetOracle(raw)
    cases=[dict(name='house'),dict(name='house_fractional_skill',skill=.3),
           dict(name='same_home',home=0),dict(name='retain_home_action',home=0,steps=[dict(action=106),dict(type='clear')]),
           dict(name='new_settlement',houses=[dict(identity=0x01000001,settlement_index=3)]),
           dict(name='enter_settlement',houses=[dict(identity=0x01000001,settlement_index=3)],steps=[dict(action=104)]),
           dict(name='already_settled',settlement_index=7,houses=[dict(identity=0x01000001,settlement_index=3)]),
           dict(name='change_settlement',settlement_index=7,houses=[dict(identity=0x01000001,settlement_index=3)],steps=[dict(action=104)]),
           dict(name='local_profession_eight',profession=8),dict(name='other_owner_profession_eight',profession=8,owner=1),
           dict(name='local_owner_one',profession=8,owner=1,local_owner=1),
           dict(name='house_clear',steps=[{},dict(type='clear'),dict(type='clear')]),
           dict(name='repeated_assignment',steps=[{},{},dict(type='clear')]),
           dict(name='plot',steps=[dict(kind=7),dict(type='clear'),dict(type='clear')]),
           dict(name='moved_plot',steps=[dict(kind=7,position=[160.25,122.])]),
           dict(name='null_house',steps=[dict(entity=-1)]),
           dict(name='stale_house',steps=[dict(identity=0x01000002)]),
           dict(name='zero_house_identity',houses=[dict(identity=0)]),
           dict(name='null_plot',steps=[dict(kind=7,entity=-1,position=[160.,122.])]),
           dict(name='removed_plot',plots=[dict(x=158.,z=120.,size=0)],steps=[dict(kind=7)]),
           dict(name='plot_distance_equal',plots=[dict(x=-2.,z=-2.,size=4)],steps=[dict(kind=7,position=[.01,0.])]),
           dict(name='plot_distance_outside',plots=[dict(x=-2.,z=-2.,size=4)],steps=[dict(kind=7,position=[.01001,0.])]),
           dict(name='flag_false',steps=[dict(flag=False)]),
           dict(name='clear_unregistered',initial_target=dict(),steps=[dict(type='clear')]),
           dict(name='invalid_clear',initial_target=dict(identity=0x01000002),steps=[dict(type='clear')]),
           dict(name='reserved_count',counters=dict(houses={'0':[5,0,0.]})),
           dict(name='skill_rounding',skill=.3,counters=dict(houses={'0':[0,3,.2]}),steps=[{},dict(type='clear')])]
    cases.extend([dict(name='no_actor',no_actor=True,steps=[{},dict(type='clear')]),
                  dict(name='no_actor_clear',no_actor=True,initial_target=dict(),steps=[dict(type='clear')]),
                  dict(name='plot_claimed',plots=[dict(x=158.,z=120.,size=4,claimed=True)],steps=[dict(kind=7)]),
                  dict(name='plot_distance_diagonal',plots=[dict(x=-2.,z=-2.,size=4)],steps=[dict(kind=7,position=[.006,.008])]),
                  dict(name='settlement_clear',houses=[dict(identity=0x01000001,settlement_index=3)],steps=[{},dict(type='clear')]),
                  dict(name='changed_skill',skills=[.3,.5],steps=[{},dict(type='clear')])])
    for case in cases:
        oracle.configure_target(case)
        case.setdefault('steps',[{}])
        case['states']=[oracle.step(step) for step in case['steps']]
    result=dict(executable_sha256=hashlib.sha256(raw).hexdigest(),cases=cases,scope=__doc__.strip(),
                adapters=[hex(a) for a in sorted(oracle.adapters)],
                native_routines={hex(a):oracle.image.read(a,b-a).hex() for a,b in [
                    (0x10033cd0,0x10033cda),(0x10033d20,0x10033d56),(0x100caeb0,0x100caf60),(0x100caf60,0x100cb0a2),
                    (0x1016ad70,0x1016adb0),(0x1016af00,0x1016b133),(0x10034160,0x1003421a),
                    (0x1007e5b0,0x1007e60a),(0x100cadc0,0x100cae1a),(0x10043cd0,0x10043cf8)]})
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original target references:',len(cases),'cases;',sum(len(c['states']) for c in cases),'transitions')


if __name__=='__main__':main()
