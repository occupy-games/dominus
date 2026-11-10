"""Original existing/revisit/new plot region loop and pool lifecycle observations.

Loaded/influence and terrain masks are explicit controlled inputs. Original
resizing, revisit scheduling, new allocation and pool instructions execute.
No original entrypoint, renderer, audio or host OS imports run.
"""
import argparse
import hashlib
import json
import struct

from tools.native_plot_resize_oracle import ResizeOracle
from tools.native_scenery_oracle import ROOT


class RegistryOracle(ResizeOracle):
    def field(self):
        kind,x,z=self.arguments(3)
        if kind not in [4,5,6]:raise ValueError('Unexpected original plot field kind '+str(kind))
        self.return_float(1. if kind==4 and self.contains(x,z) else self.blight.get((x,z),0.) if kind==5 else 0.)

    def configure_registry(self,case):
        self.configure_resize(case)
        self.bounds=case.get('bounds',[156,116,172,132])
        self.set_integer(0x110a4978,1)
        self.set_integer(0x1060c764,case.get('minimum',2))
        self.set_integer(0x110a4974,case.get('maximum',8))
        count=len(self.plots)
        self.set_integer(0x10f8f8dc,count)
        self.set_integer(0x10f8f8e0,count|((count-1 if count else 0xffff)<<16))
        for i in range(1024):
            if i<count: next_,previous=i-1 if i else 0xffff,i+1 if i<count-1 else 0xffff
            else: next_,previous=i+1 if i<1023 else 0xffff,i-1 if i>count else 0xffff
            self.cpu.mem_write(self.POOL+i*0x74,struct.pack('<HH',next_,previous))
        for item in self.plots:
            p=self.POOL+item['id']*0x74
            self.set_integer(p+0x18,item['size'])
            self.set_integer(p+0x1c,item['x'])
            self.set_integer(p+0x20,item['z'])
            self.set_float(p+0x28,-1.)
            self.set_float(p+0x50,case.get('progress',1.))
        self.cpu.mem_write(self.FLAT,bytes(1024*128))
        x0,z0,x1,z1=self.bounds
        for z in range(z0,z1):
            for x in range(x0,x1):self.bit(self.FLAT,x,z,True)
        for x,z in case.get('nonflat',[]):self.bit(self.FLAT,x,z,False)
        self.call(0x1025e5e0,limit=100000000)
        self.adapters[0x100f1ba0]=lambda:self.return_integer()
        self.handles.append(self.cpu.hook_add(self.hook_kind,self.hook,begin=0x100f1ba0,end=0x100f1ba0))

    def region(self,tile):
        frame=self.STACK+0x80000
        self.cpu.mem_write(frame-0x2000,bytes(0x2000))
        self.set_integer(frame-0x44,tile[0])
        self.set_integer(frame-0x5c,tile[1])
        self.cpu.reg_write(self.regs.UC_X86_REG_ESP,frame-0x3000)
        self.cpu.reg_write(self.regs.UC_X86_REG_EBP,frame)
        self.cpu.mem_write(self.SCRATCH+0x700,b'\xdb\xe3')
        self.cpu.emu_start(self.SCRATCH+0x700,self.SCRATCH+0x702)
        self.cpu.emu_start(0x102379c8,0x10239cd5,count=10000000)
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=0x10239cd5:raise ValueError('Original region loop did not complete')

    def advance(self,delta):
        self.call(0x10236110,struct.unpack('<I',struct.pack('<f',delta)))

    def change_flatness(self,points,bounds=None):
        if bounds is not None:self.bounds=bounds
        x0,z0,x1,z1=self.bounds
        for z in range(z0,z1):
            for x in range(x0,x1): self.bit(self.FLAT,x,z,True)
        for x,z in points:self.bit(self.FLAT,x,z,False)
        self.call(0x1025e5e0,limit=100000000)

    def snapshot(self):
        active=[]
        index=self.integer(0x10f8f8e2)&0xffff
        while index!=0xffff:
            if len(active)>=1024:raise ValueError('Original active plot list cycle')
            p=self.POOL+index*0x74
            active.append({'id':index,'x':self.float(p+8),'z':self.float(p+12),'size':self.integer(p+4),
                           'height':self.float(p+16),'claimed':bool(self.integer(p+0x4c)),
                           'stored_size':self.integer(p+0x18),'stored_x':self.integer(p+0x1c),'stored_z':self.integer(p+0x20),
                           'progress':self.float(p+0x50)})
            index=self.integer(p)&0xffff
        free=[]
        index=self.integer(0x10f8f8e0)&0xffff
        while index!=0xffff:
            if len(free)>=1024:raise ValueError('Original free plot list cycle')
            free.append(index)
            index=self.integer(self.POOL+index*0x74)&0xffff
        return {'plots':active,'free':free,'owners':{str(cell):(self.integer(node+0x14)-self.POOL)//0x74 for cell,node in self.nodes.items() if self.integer(node+0x14)}}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_plot_registry.json'))
    args=parser.parse_args()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    cases=[{'name':'empty','plots':[]},{'name':'grow_and_fill'},{'name':'minimum_four','minimum':4},
           {'name':'border_damage','nonflat':[[160,120]]},{'name':'interior_damage','nonflat':[[161,121]]},
           {'name':'claimed','plots':[{'id':0,'x':160,'z':120,'size':4,'claimed':True}]},
           {'name':'neighbor_merge','plots':[{'id':0,'x':160,'z':120,'size':4,'claimed':False},
                                           {'id':1,'x':158,'z':120,'size':2,'claimed':False}]},
           {'name':'neighbor_claimed','plots':[{'id':0,'x':160,'z':120,'size':4,'claimed':False},
                                             {'id':1,'x':158,'z':120,'size':2,'claimed':True}]}]
    for axis, edge, bounds in [('x',128,[124,116,140,132]),('x',192,[188,116,204,132]),
                               ('z',96,[156,92,172,108]),('z',160,[156,156,172,168])]:
        for offset in [0,1 if edge in [128,96] else -1]:
            plot={'id':0,'x':160,'z':120,'size':4,'claimed':False}
            plot[axis]=edge+offset
            cases.append(dict(name=f'boundary_{axis}_{edge}_{offset}',bounds=bounds,plots=[plot]))
    cases.append(dict(name='removed_slot_reuse',nonflat=[[161,121]],steps=
                      [{'region':[5,4]}]+[{'delta':.1} for _ in range(5)]+
                      [{'nonflat':[],'bounds':[156,116,180,132]},{'region':[5,4]}]))
    cases.append(dict(name='overlapping_regions',bounds=[140,108,180,140],steps=
                      [{'region':tile} for tile in [[5,4],[4,4],[5,3],[5,4]]]))
    for case in cases:
        oracle=RegistryOracle(raw)
        oracle.configure_registry(case)
        case['bounds']=oracle.bounds
        case.setdefault('steps',[{'region':[5,4]}]+[{'delta':.1} for _ in range(6)]+[{'region':[5,4]}])
        case['states']=[]
        for step in case['steps']:
            if 'region' in step:oracle.region(step['region'])
            elif 'delta' in step:oracle.advance(step['delta'])
            else:oracle.change_flatness(step['nonflat'],step.get('bounds'))
            case['states'].append(oracle.snapshot())
        print('Original registry case:',case['name'],len(case['states'][-1]['plots']),'slots',flush=True)
    result={'executable_sha256':hashlib.sha256(raw).hexdigest(),'cases':cases,
            'progress_rate':struct.unpack('<d',oracle.image.read(0x104ec570,8))[0],
            'native_routines':{hex(a):oracle.image.read(a,b-a).hex() for a,b in [(0x102379c8,0x10239cd5),(0x10236110,0x102362fb),(0x10044110,0x100441b8)]},
            'adapters':[hex(a) for a in sorted(oracle.adapters)],
            'scope':'Original region existing/revisit/new allocation loop and plot-pool lifecycle over controlled loaded/influence/flat/scenery/building/biome fields. Global availability/dirty marking, native AOI generation, beauty and follower claims are separate.'}
    (ROOT/args.output).write_text(json.dumps(result,separators=(',',':'))+'\n')


if __name__=='__main__':main()
