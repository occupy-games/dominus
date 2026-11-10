"""Bounded original new-plot allocation with explicit loaded/eligibility inputs.

This executes the native scan, cell gates, pool allocation and footprint
reservation. It does not emulate existing-plot resizing, claims or presentation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from tools.campaign import packed_map
from tools.current_cards import decode_archive, rows
from tools.native_plot_oracle import PlotOracle, scenery_cells
from tools.native_scenery_oracle import ROOT


class AllocationOracle(PlotOracle):
    def configure_allocation(self,terrain,occupied,plotrot,biomes,configuration,bounds,sizes):
        self.configure_plots(terrain,occupied,[(x,z) for z in range(2,6) for x in range(3,7)])
        self.masks()
        self.plotrot=plotrot
        self.bounds=bounds
        self.output=[]
        self.nodes={}
        self.head=self.SCRATCH+0x6000
        self.set_integer(0x10f9f4ac,self.head)
        self.set_integer(0x10f8f8d8,self.POOL)
        self.set_integer(0x10f8f8dc,0)
        self.set_integer(0x10f8f8e0,0xffff0000)
        for index in range(1024):
            self.cpu.mem_write(self.POOL+index*0x74,struct.pack('<HH',index+1 if index<1023 else 0xffff,0xffff))
        self.biome_table(biomes)
        for name,pointer in [('loc2Start',0x105b2d08),('loc3Start',0x105b2d0c),
                             ('biome1Index',0x1060fd2c),('biome2Index',0x1060fd30),('biome3Index',0x1060fd34)]:
            self.set_float(pointer,float(configuration[name]))
        for index,(minimum,maximum) in enumerate(sizes):
            self.set_integer(0x1060c758+index*4,minimum)
            self.set_integer(0x110a4968+index*4,maximum)
        self.set_integer(0x1060c764,min(value[0] for value in sizes if value[1]>0))
        self.set_integer(0x110a4974,max(value[1] for value in sizes))
        self.set_integer(0x110a4978,7) # Original first tent allows biome012.
        self.set_integer(0x10fcd4f4,1) # Suppress the first-plot audio announcement.
        self.adapters.update({
            0x10144820:self.loaded_region,
            0x101453c0:self.read_plotrot,
            0x10145330:self.plotrot_pointer,
            0x100cf550:self.influence_field,
            0x10235dd0:lambda:self.return_integer(), # beauty fractions, not layout
            0x10235f20:lambda:self.return_integer(), # scenery beauty, not layout
            0x101c0760:self.insert_cell, # ordered storage only; native reservation loop runs
            0x100f1a00:self.register,
            0x10254390:lambda:self.return_integer(), # original particle request
            0x102545c0:lambda:self.return_integer(), # original audio event
        })
        for handle in self.handles: self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def biome_table(self,biomes):
        self.cpu.mem_write(0x10fcd000,bytes(32*20))
        for index,row in enumerate(biomes[1:]):
            if len(row)<5: continue
            if index>=32: raise ValueError('Original biome table budget exceeded')
            self.cpu.mem_write(0x10fcd000+index*20,struct.pack('<ffffi',*[float(v) for v in row[:4]],int(row[4])))

    def classify(self,points):
        result=[]
        for x,z in points:
            args=struct.unpack('<II',struct.pack('<ff',x,z))
            scheme=self.call(0x1025b570,args)
            result.append([x,z,scheme if scheme<0x80000000 else scheme-0x100000000,self.call(0x1025b670,args)])
        return result

    def contains(self,x,z):
        x0,z0,x1,z1=self.bounds
        return x0<=x<x1 and z0<=z<z1

    def loaded_region(self):
        self.return_integer(int(self.contains(*self.arguments(2))))

    def read_plotrot(self):
        kind,x,z=self.arguments(3)
        if kind!=2: raise ValueError('Unexpected original byte-field read')
        self.return_integer(self.plotrot[z*1024+x] if x<1024 and z<1024 else 0)

    def plotrot_pointer(self):
        kind,x,z=self.arguments(3)
        if kind!=2: raise ValueError('Unexpected original byte-field pointer')
        self.cpu.mem_write(self.SCRATCH+0x9000,bytes([self.plotrot[z*1024+x]]))
        self.return_integer(self.SCRATCH+0x9000)

    def influence_field(self):
        kind,x,z=self.arguments(3)
        if kind not in [4,5,6]: raise ValueError('Unexpected original influence/blight input')
        # Explicit controlled fields. The rectangular loaded domain is clipped
        # inside the original initial influence; this is not a full AOI raster.
        self.return_float(1. if kind==4 and self.contains(x,z) else 0.)

    def insert_cell(self):
        if self.cpu.reg_read(self.regs.UC_X86_REG_ECX)!=0x10f9f4ac:
            raise ValueError('Unknown native cell index')
        output,hint,value=self.arguments(3)
        key=self.integer(value)
        if key not in self.nodes:
            pointer=self.GRIDS+0x200000+len(self.nodes)*32
            self.nodes[key]=pointer
            self.set_integer(pointer+0x10,key)
            parent=self.head
            offset=4
            child=self.integer(parent+offset)
            while child:
                parent=child
                offset=8 if key<self.integer(child+0x10) else 12
                child=self.integer(parent+offset)
            self.set_integer(parent+offset,pointer)
        self.set_integer(output,self.nodes[key])
        self.return_integer(output,pop=12)

    def register(self):
        pointer,kind,x,z,radius,circular=self.arguments(6)
        if kind!=7 or circular!=1: raise ValueError('Unknown native plot registration')
        self.output.append({'id':(pointer-self.POOL)//0x74,'x':self.float(pointer+8),'z':self.float(pointer+12),
                            'size':self.integer(pointer+4),'height':self.float(pointer+16),
                            'center':list(struct.unpack('<ff',struct.pack('<II',x,z))),
                            'radius':struct.unpack('<f',struct.pack('<I',radius))[0]})
        self.return_integer(pop=24)

    def allocate_region(self,tile):
        frame=self.STACK+0x80000
        self.set_integer(frame-0x44,tile[0])
        self.set_integer(frame-0x5c,tile[1])
        self.cpu.reg_write(self.regs.UC_X86_REG_ESP,frame-0x1000)
        self.cpu.reg_write(self.regs.UC_X86_REG_EBP,frame)
        self.cpu.mem_write(self.SCRATCH+0x700,b'\xdb\xe3')
        self.cpu.emu_start(self.SCRATCH+0x700,self.SCRATCH+0x702)
        try: self.cpu.emu_start(0x102397f5,0x10239cd5,count=10000000)
        except Exception as error:
            raise ValueError('Original plot allocation failed at '+hex(self.cpu.reg_read(self.regs.UC_X86_REG_EIP))) from error
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=0x10239cd5: raise ValueError('Original plot instruction budget exhausted')
        return self.output


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'game/tests/fixtures/source_plot_allocation.json')
    args=parser.parse_args()
    directory=ROOT/'game/assets/original/campaign'
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    scenery=(directory/'homeworld6-scenery.bin').read_bytes()
    fields,*_=packed_map(ROOT/'data/godus2_4/stream/Homeworld6.pack')
    archive=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    files=decode_archive(archive)
    configuration={row[0]:row[1] for path in ['config.csv','balance/config.csv'] for row in rows(files,path) if len(row)>1}
    bounds=[150,119,170,138]
    sizes=[[4,4],[0,0],[0,0]]
    result={'executable_sha256':hashlib.sha256(raw).hexdigest(),'source_sha256':hashlib.sha256(archive).hexdigest(),
            'terrain_sha256':hashlib.sha256(fields['terrain']).hexdigest(),'plotrot_sha256':hashlib.sha256(fields['plotrot']).hexdigest(),
            'scenery_sha256':hashlib.sha256(scenery).hexdigest(),'bounds':bounds,'tile':[5,4],'sizes':sizes,'biome_mask':7,
            'plotrot_region':bytes(fields['plotrot'][z*1024+x] for z in range(bounds[1],bounds[3]) for x in range(bounds[0],bounds[2])).hex(),
            'configuration':{key:configuration[key] for key in ['loc2Start','loc3Start','biome1Index','biome2Index','biome3Index']},
            'biomes':rows(files,'initialworldsetup6/biomes.csv'), 'cases':[],
            'scope':'New plots in one dirty region, no existing plots; explicit clipped loaded/influence domain. Not native global initialization, resizing, claims, beauty or construction.'}
    examples=[{'name':'cleared','terrain_edits':[]},
              {'name':'sculpted','terrain_edits':[[161,120,20]]},
              {'name':'forbidden_byte','terrain_edits':[[161,120,20]],'plotrot_edits':[[159,122,65]]},
              {'name':'byte64','terrain_edits':[[161,120,20]],'plotrot_edits':[[159,122,64]]},
              {'name':'byte127','terrain_edits':[[161,120,20]],'plotrot_edits':[[159,122,127]]},
              {'name':'byte128','terrain_edits':[[161,120,20]],'plotrot_edits':[[159,122,128]]},
              {'name':'flat_patch','terrain_patch':[150,119,171,141,20]},
              {'name':'mixed_sizes','terrain_patch':[150,119,171,141,20],'sizes':[[4,5],[0,0],[0,0]]},
              {'name':'wrong_location','terrain_patch':[150,119,171,141,25]}]
    for example in examples:
        terrain=bytearray(fields['terrain'])
        for x,z,value in example.get('terrain_edits',[]): terrain[z*1024+x]=value
        if 'terrain_patch' in example:
            x0,z0,x1,z1,value=example['terrain_patch']
            for z in range(z0,z1):
                for x in range(x0,x1): terrain[z*1024+x]=value
        plotrot=bytearray(fields['plotrot'])
        for x,z,value in example.get('plotrot_edits',[]): plotrot[z*1024+x]=value
        oracle=AllocationOracle(raw)
        oracle.configure_allocation(bytes(terrain),scenery_cells(scenery,True),bytes(plotrot),result['biomes'],configuration,bounds,example.get('sizes',sizes))
        plots=oracle.allocate_region(result['tile'])
        result['cases'].append(dict(example,plots=plots,adapters=[hex(a) for a in sorted(oracle.touched)]))
    result['biome_cases']=[]
    for scope in ['initialworldsetup6','initialworldsetup7']:
        table=rows(files,scope+'/biomes.csv')
        oracle.biome_table(table)
        points=[(x,z) for z in range(0,1024,64) for x in range(0,1024,64)]
        for row in table[1:]:
            if len(row)<5: continue
            x,z,radius=float(row[0]),float(row[1]),float(row[3])
            points.extend([(x,z),(x+radius,z),(x+radius-.125,z),(x+radius+.125,z)])
        result['biome_cases'].append({'scope':scope,'rows':table,'samples':oracle.classify(points),
                                     'sha256':hashlib.sha256(files[scope+'/biomes.csv']).hexdigest()})
    result['native_routines']={hex(start):oracle.image.read(start,end-start).hex() for start,end in [
        (0x102397f5,0x10239b90),(0x10237580,0x10237654),(0x10235d50,0x10235dd0),
        (0x10236030,0x10236109),(0x102358b0,0x102358de),(0x1025b570,0x1025b693),
        (0x10153980,0x101539b8),(0x10257570,0x10257602)]}
    result['adapters']=sorted({a for case in result['cases'] for a in case['adapters']})
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print('Original new plots:',[(case['name'],len(case['plots'])) for case in result['cases']])


if __name__=='__main__': main()
