"""Execute original rock refresh and motion loops over controlled object inputs.

Only raw terrain storage and lock/cookie services are adapted. No original
entrypoint, renderer, OS or audio services run. Trees and regeneration are absent.
"""
import argparse
import json
from pathlib import Path
import struct

from tools.native_scenery_oracle import Oracle, ROOT
from tools.rock_motion import extract


class MotionOracle(Oracle):
    def configure_motion(self,objects,duration):
        self.configure(bytes([20])*(1024*1024),b'',b'',[])
        self.adapters={0x10144780:lambda:self.return_integer(),0x10144790:lambda:self.return_integer(),
                       0x101450b0:self.height,0x1035f830:lambda:self.return_integer()}
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.objects=objects
        self.set_integer(0x105e3040,0xffff)
        self.set_float(0x105da89c,duration)
        self.queue=self.SCRATCH+0x5000
        self.set_integer(0x10f2e808,self.queue)
        self.set_integer(0x10f2e80c,0)
        self.set_integer(0x10f2e810,0xffff0000)
        for index in range(12):
            self.cpu.mem_write(self.queue+index*16,struct.pack('<HH',index+1 if index<11 else 0xffff,0xffff))
        for index,item in enumerate(objects):
            pointer=self.POOL+index*0xec
            self.set_float(pointer+0x28,item['x'])
            self.set_float(pointer+0x2c,item['z'])
            self.set_float(pointer+0x30,item['height'])
            self.set_integer(pointer+0x34,25) # Original rock1/boulder6 classification.
            for cell in item['cells']:
                x,z=cell%1024,cell//1024
                tile=(z//32)*32+x//32
                if tile not in self.grids:
                    grid=self.GRIDS+len(self.grids)*2048
                    self.grids[tile]=grid
                    self.cpu.mem_write(grid,b'\xff'*2048)
                    self.set_integer(0x10f2d7fc+tile*4,grid)
                self.cpu.mem_write(self.grids[tile]+((z%32)*32+x%32)*2,struct.pack('<H',index))

    def refresh(self,tiles):
        self.cpu.mem_write(0x10f6e858,bytes(128))
        for x,z in tiles:
            pointer=0x10f6e858+z*4
            self.set_integer(pointer,self.integer(pointer)|(1<<x))
        self.call(0x10260e90,limit=10000000)

    def advance(self,delta):
        frame=self.STACK+0x80000
        self.set_float(frame+8,delta)
        self.cpu.reg_write(self.regs.UC_X86_REG_ESP,frame-0x200)
        self.cpu.reg_write(self.regs.UC_X86_REG_EBP,frame)
        self.cpu.mem_write(self.SCRATCH+0x700,b'\xdb\xe3')
        self.cpu.emu_start(self.SCRATCH+0x700,self.SCRATCH+0x702)
        self.cpu.emu_start(0x1015da0e,0x1015db18,count=1000000)
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=0x1015db18: raise ValueError('Original rock motion did not finish')

    def snapshot(self):
        queue=[]
        index=self.integer(0x10f2e812)&0xffff
        while index!=0xffff:
            pointer=self.queue+index*16
            if len(queue)>=12: raise ValueError('Invalid native motion list')
            queue.append({'object':self.integer(pointer+12)&0xffff,'start':self.float(pointer+4),'elapsed':self.float(pointer+8)})
            index=self.integer(pointer)&0xffff
        return {'heights':[self.float(self.POOL+i*0xec+0x30) for i in range(len(self.objects))],'queue':queue}


def object_at(x,z):
    # Plain controlled objects, with the original two-by-two rock footprint.
    x,z=struct.unpack('<ff',struct.pack('<ff',x,z))
    ox,oz=int(x-.5)//1,int(z-.5)//1
    return {'x':x,'z':z,'height':6.,'cells':[(oz+dz)*1024+ox+dx for dz in range(2) for dx in range(2)]}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'game/tests/fixtures/source_rock_motion.json')
    args=parser.parse_args()
    config=extract()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    single=[object_at(161,123)]
    sequence=lambda level,delta,count:[{'raw':level,'refresh':i==0,'delta':delta} for i in range(count)]
    cases=[{'name':'unchanged','objects':single,'steps':sequence(20,.1,1)},
           {'name':'raise','objects':single,'steps':sequence(23,.1,12)},
           {'name':'lower','objects':single,'steps':sequence(17,.1,12)},
           {'name':'exact_duration','objects':single,'steps':sequence(23,.25,4)+[{'raw':23,'delta':.001}]},
           {'name':'retarget','objects':single,'steps':sequence(23,.1,3)+sequence(25,.1,11)},
           {'name':'moving_target','objects':single,'steps':sequence(23,.1,3)+[{'raw':25,'delta':.1} for _ in range(9)]},
           {'name':'capacity','objects':[object_at(101+2*i,101) for i in range(13)],'steps':sequence(23,.1,12)},
           {'name':'tile_boundary','objects':[object_at(127.8,127.8)],'steps':sequence(24,.1,12)}]
    result={'configuration':config,'cases':[],'scope':'Controlled rock-only occupancy/terrain, original dirty scan and motion pool. Trees, regeneration and scene updates are absent.'}
    for case in cases:
        oracle=MotionOracle(raw)
        oracle.configure_motion(case['objects'],case.get('duration',config['duration']))
        tiles=sorted({(cell%1024//32,cell//1024//32) for item in case['objects'] for cell in item['cells']},key=lambda p:(p[1],p[0]))
        states=[]
        for step in case['steps']:
            oracle.terrain=bytes([step['raw']])*(1024*1024)
            if step.get('refresh'): oracle.refresh(tiles)
            oracle.advance(step['delta'])
            states.append(oracle.snapshot())
        result['cases'].append(dict(case,tiles=tiles,states=states))
    result['adapters']=[hex(a) for a in sorted(oracle.adapters)]
    args.output.write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Original rock motion:',len(cases),'cases;',[(c['name'],len(c['states'][0]['queue']),c['states'][-1]['heights'][0]) for c in result['cases']])


if __name__=='__main__':main()
