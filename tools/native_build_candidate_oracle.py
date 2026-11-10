"""Run the original builder selector over explicit ordered plot candidates.

The original scan, house selector, capacity lookup, reference update and scoring
execute. Spatial-list membership/order, influence and raw height are injected
inputs, not a claim to execute navigation or the full follower decision tree.
No original entrypoint, renderer, OS service or audio runs.
"""
import argparse
import hashlib
import json
import struct

from tools.build_candidates import extract
from tools.house_selection import extract as selection
from tools.native_house_selection_oracle import SelectionOracle
from tools.native_scenery_oracle import ROOT


class BuildCandidateOracle(SelectionOracle):
    def configure_candidates(self, data):
        self.configure_selection(selection())
        for row in self.entries:
            values=data['values'][row['id']]
            for key,offset in [('build capacity',0x44),('buildplotpriority',0xdc)]:
                self.set_float(0x10fc241c+row['index']*0x130+offset,values[key])
        self.cpu.mem_write(0x10fcd000,bytes(32*20))
        self.set_float(0x105b2d08,25)
        self.set_float(0x105b2d0c,36)
        self.set_integer(0x10f8f8d8,self.POOL)
        self.set_integer(0x10f8f8e4,self.SCRATCH+0x6000)
        self.set_integer(self.SCRATCH+0x6000,self.POOL)
        self.adapters.update({
            0x1002c670:self.actor_record,
            0x10168960:lambda:self.return_integer(int(self.case.get('disabled',False))),
            0x1012ec90:self.spatial_list,
            0x10257570:self.influence,
            0x1025c120:self.raw_height,
        })
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def actor_record(self):
        self.set_integer(self.SCRATCH+0x7000+0x258,self.case.get('actor_mode',0))
        self.return_integer(self.SCRATCH+0x7000)

    def spatial_list(self):
        args=self.arguments(10)
        if args[0]!=0x83:raise ValueError('Unexpected native builder kind mask')
        self.query=list(args)
        candidates=self.case.get('plots',[])
        self.set_integer(0x10c64e68,len(candidates))
        for i,plot in enumerate(candidates):
            pointer=self.POOL+plot['id']*0x74
            node=0x10c58e68+i*12
            payload=self.SCRATCH+0x3000+i*16
            self.cpu.mem_write(pointer,bytes(0x74))
            self.set_integer(pointer+4,plot['size'])
            self.set_float(pointer+8,plot['x'])
            self.set_float(pointer+12,plot['z'])
            self.set_float(pointer+16,plot.get('height',6.))
            self.set_integer(pointer+0x4c,int(plot.get('claimed',False)))
            self.set_integer(0x10f8f8e4+4+plot['id']*4,plot.get('assigned',0))
            self.set_integer(0x10f8f8e4+0x1004+plot['id']*4,plot.get('workers',0))
            self.cpu.mem_write(payload,struct.pack('<IIII',pointer,0,7,0))
            self.cpu.mem_write(node,struct.pack('<III',payload,node+12 if i+1<len(candidates) else 0,0))
        if candidates:self.set_integer(0x10c58e68+8,0x10c58e68+(len(candidates)-1)*12)
        self.return_integer(0x10c58e68 if candidates else 0)

    def at_center(self,x,z):
        x,z=struct.unpack('<ff',struct.pack('<II',x,z))
        for plot in self.case.get('plots',[]):
            half=plot['size']*.5
            if (plot['x']+half,plot['z']+half)==(x,z):return plot
        raise ValueError('Unknown original candidate center '+str((x,z)))

    def influence(self):
        x,z,power=self.arguments(3)
        if power!=1:raise ValueError('Unexpected builder influence flag')
        # This flag is an important independent observation: it requests the
        # source power/max gate, not the stricter fresh-plot construction gate.
        for plot in self.case.get('plots',[]):
            half=plot['size']*.5
            if (int(plot['x']+half),int(plot['z']+half))==(x,z):
                self.return_integer(int(plot.get('influence',True)));return
        raise ValueError('Unknown native builder influence center')

    def raw_height(self):
        plot=self.at_center(*self.arguments(2))
        self.return_integer(plot.get('raw_height',20))

    def choose(self,case):
        self.case=case
        self.query=[]
        self.profile(dict(unlocks=case.get('unlocks',['PlotsAppear']),biome_locked=True))
        self.cpu.mem_write(self.SCRATCH+0x5000,bytes(20))
        position=case.get('position',[157.,119.,6.])
        floats=[*position,case.get('radius',12.),case.get('height_balance',1.)]
        args=[0,0,*struct.unpack('<5I',struct.pack('<5f',*floats)),self.SCRATCH+0x5000,
              struct.unpack('<I',struct.pack('<f',case.get('priority_scale',1.)))[0],0]
        action=self.call(0x100cd790,args,limit=2000000)
        reference=self.integer(self.SCRATCH+0x5000+4)
        frame=self.STACK+0x80000-len(args)*4-8
        return dict(action=action,plot=(reference-self.POOL)//0x74 if reference else -1,
                    center=[self.float(self.SCRATCH+0x5008),self.float(self.SCRATCH+0x500c)] if reference else [],
                    score=self.float(frame-8) if self.query else 0.)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_build_candidates.json'))
    args=parser.parse_args()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    data=extract()
    oracle=BuildCandidateOracle(raw)
    oracle.configure_candidates(data)
    base=dict(id=0,x=158.,z=120.,size=4)
    cases=[dict(name='first_plot',plots=[base]),dict(name='empty',plots=[]),
           dict(name='locked',unlocks=[],plots=[base]),
           dict(name='full',plots=[dict(base,workers=1)]),
           dict(name='reserved_only',plots=[dict(base,assigned=1)]),
           dict(name='outside_influence',plots=[dict(base,influence=False)]),
           dict(name='removed',plots=[dict(base,size=0)]),
           dict(name='selected_plot_flag',plots=[dict(base,claimed=True)]),
           dict(name='disabled',disabled=True,plots=[base]),
           dict(name='actor_mode_six',actor_mode=6,plots=[base])]
    for scale in [0.,-1.,.3,2.]:cases.append(dict(name='scale_'+str(scale),priority_scale=scale,plots=[base]))
    for radius in [0.,.5,2.,3.,12.]:cases.append(dict(name='radius_'+str(radius),radius=radius,plots=[base]))
    for raw_height in [0,19,20,24,25,36]:
        cases.append(dict(name='height_'+str(raw_height),plots=[dict(base,raw_height=raw_height)]))
    for height in [6.,7.5,10.8]:cases.append(dict(name='band_'+str(height),plots=[dict(base,height=height)]))
    other=dict(base,id=1,x=152.,z=120.)
    cases.extend([dict(name='closer_wins',plots=[base,dict(other,x=155.)]),
                  dict(name='equal_first_wins',plots=[base,other]),
                  dict(name='equal_reversed',plots=[other,base])])
    for size in [4,8,12,16]:
        for workers in [0,1,4]:
            cases.append(dict(name=f'lowland_{size}_{workers}',unlocks=['PlotsAppear','Low_Rank_1','Low_Rank_2','Low_Rank_3'],plots=[dict(base,size=size,workers=workers)]))
    for x,z,height in [(160.,122.,6.),(160.125,122.5,6.3),(130.375,110.875,7.5),(157.,119.,0.3)]:
        for balance in [0.,.3,1.,2.5]:
            cases.append(dict(name=f'fractional_{x}_{z}_{height}_{balance}',position=[x,z,height],height_balance=balance,plots=[base]))
    for case in cases:case['expected']=oracle.choose(case)
    result={key:data[key] for key in ['source_sha256','table_sha256','executable_sha256','native_routines']}
    result.update(cases=cases,adapters=[hex(a) for a in sorted(oracle.touched)],
                  scope='Original builder selector with explicit ordered plot candidates only; original house choice, worker cap, source score and target reference. Spatial search, actor record guard, influence and raw height are supplied. Non-plot candidates, dispatch, navigation and construction are not captured.')
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original builder plot candidates:',len(cases),'cases;',[(c['name'],c['expected']) for c in cases[:9]])


if __name__=='__main__':main()
