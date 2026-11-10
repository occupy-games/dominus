"""Execute one original existing-plot maintenance iteration, with storage adapters.

The size/movement/merge decisions, predicates and footprint registration loops
execute original CPU instructions. Only ordered-map node allocation/erasure and
presentation/diagnostic services are adapted. No entrypoint or host imports run.
"""
import argparse
import hashlib
import json

from tools.native_existing_plot_oracle import ExistingPlotOracle
from tools.native_scenery_oracle import ROOT


class ResizeOracle(ExistingPlotOracle):
    def configure_resize(self,case):
        if not getattr(self,'resize_ready',False):
            self.configure_existing()
            self.resize_ready=True
        # Independent uniform-level cases: reset their controlled bit fields,
        # not the CPU's original mask-generation routine on every probe.
        self.cpu.mem_write(self.FLAT+110*128,b'\xff'*(30*128))
        self.cpu.mem_write(self.SCENERY+110*128,bytes(30*128))
        self.cpu.mem_write(0x10f2e858+110*128,bytes(30*128))
        self.adapters.update({0x102374f0:self.erase_cell,0x101c0760:self.insert,
                              0x100f1b20:lambda:self.return_integer(pop=12),
                              0x10179af0:lambda:self.return_integer()})
        for handle in self.handles:self.cpu.hook_del(handle)
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]
        self.inputs=case
        self.plots=case.get('plots',[{'id':0,'x':160,'z':120,'size':4,'claimed':False}])
        owners={}
        for item in self.plots:
            p=self.POOL+item['id']*0x74
            self.set_integer(p+4,item['size'])
            self.set_float(p+8,item['x'])
            self.set_float(p+12,item['z'])
            self.set_float(p+16,6.)
            self.set_integer(p+0x4c,int(item['claimed']))
            for z in range(item['z'],item['z']+item['size']):
                for x in range(item['x'],item['x']+item['size']): owners[z*1024+x]=p
        self.owners(owners)
        self.set_integer(0x10f9f4b8,self.POOL+case['selected']*0x74 if case.get('selected') is not None else 0)
        for x,z in case.get('nonflat',[]):self.bit(self.FLAT,x,z,False)
        for x,z in case.get('scenery',[]):self.bit(self.SCENERY,x,z,True)
        for x,z in case.get('blocked',[]):self.bit(0x10f2e858,x,z,True)
        for index in range(3):
            self.set_integer(0x1060c758+index*4,case.get('minimum',2))
            self.set_integer(0x110a4968+index*4,case.get('maximum',8))

    def erase_cell(self):
        key=self.integer(self.arguments(1)[0])
        values={cell:self.integer(node+0x14) for cell,node in self.nodes.items() if cell!=key}
        self.owners(values)
        self.return_integer(1,pop=4)

    def insert(self):
        output,hint,value=self.arguments(3)
        key=self.integer(value)
        values={cell:self.integer(node+0x14) for cell,node in self.nodes.items()}
        values.setdefault(key,0)
        self.owners(values)
        self.set_integer(output,self.nodes[key])
        self.return_integer(output,pop=12)

    def iteration(self):
        frame=self.STACK+0x80000
        self.cpu.mem_write(frame-0x2000,bytes(0x2000))
        target=self.POOL+self.inputs.get('target',0)*0x74
        self.set_integer(frame-0xab0,target)
        self.cpu.reg_write(self.regs.UC_X86_REG_EBX,1)
        self.cpu.reg_write(self.regs.UC_X86_REG_EDI,0)
        self.cpu.reg_write(self.regs.UC_X86_REG_ESP,frame-0x3000)
        self.cpu.reg_write(self.regs.UC_X86_REG_EBP,frame)
        self.cpu.mem_write(self.SCRATCH+0x700,b'\xdb\xe3')
        self.cpu.emu_start(self.SCRATCH+0x700,self.SCRATCH+0x702)
        self.cpu.emu_start(0x10237a90,0x102397ed,count=2000000)
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=0x102397ed:
            raise ValueError('Original plot maintenance iteration did not finish at '+hex(self.cpu.reg_read(self.regs.UC_X86_REG_EIP)))
        output=[]
        for item in self.plots:
            p=self.POOL+item['id']*0x74
            output.append({'id':item['id'],'x':self.float(p+8),'z':self.float(p+12),'size':self.integer(p+4),
                           'claimed':bool(self.integer(p+0x4c))})
        size=self.integer(frame-0x30)
        return {'plots':output,'revisit':[(self.integer(frame-0xab0+4*i)-self.POOL)//0x74 for i in range(size)],
                'owners':{str(cell):(self.integer(node+0x14)-self.POOL)//0x74 for cell,node in self.nodes.items() if self.integer(node+0x14)}}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/tests/fixtures/source_plot_resize.json'))
    args=parser.parse_args()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    cases=[{'name':'flat'},{'name':'at_maximum','maximum':4},{'name':'selected','selected':0},
           {'name':'border_lost','nonflat':[[160,120]]},{'name':'interior_lost','nonflat':[[161,121]]}]
    cases.extend([{'name':'one_size_available','maximum':5},{'name':'valid_claimed','plots':[{'id':0,'x':160,'z':120,'size':4,'claimed':True}]}])
    for x,z in [(160,120),(163,120),(160,123),(163,123),(161,120),(162,120),(160,121),(160,122),(163,121),(163,122),(161,123),(162,123),(161,121)]:
        for key in ['nonflat','scenery','blocked']:
            cases.append({'name':f'{key}_{x}_{z}',key:[[x,z]]})
    for edge,points in [('left',[[160,z] for z in range(120,124)]),('right',[[163,z] for z in range(120,124)]),
                        ('top',[[x,120] for x in range(160,164)]),('bottom',[[x,123] for x in range(160,164)]),
                        ('all_corners',[[160,120],[163,120],[160,123],[163,123]])]:
        cases.append({'name':edge+'_lost','nonflat':points})
    for x,z in [(158,120),(164,120),(160,124),(160,118),(158,118),(164,124)]:
        for claimed in [False,True]:
            cases.append({'name':f'neighbor_{x}_{z}_{claimed}', 'plots':[
                {'id':0,'x':160,'z':120,'size':4,'claimed':False},
                {'id':1,'x':x,'z':z,'size':2,'claimed':claimed}]})
    cases.append({'name':'four_smaller_neighbors','plots':[
        {'id':0,'x':160,'z':120,'size':4,'claimed':False},
        *[{'id':i+1,'x':x,'z':z,'size':2,'claimed':False} for i,(x,z) in enumerate([(158,120),(164,120),(160,124),(160,118)])]]})
    o=ResizeOracle(raw)
    for case in cases:
        o.configure_resize(case)
        case['expected']=o.iteration()
    result={'executable_sha256':hashlib.sha256(raw).hexdigest(),'cases':cases,
            'native_routines':{hex(a):o.image.read(a,b-a).hex() for a,b in [(0x10237a90,0x102397ed),(0x10236370,0x102374ed),
                                                                       (0x10237580,0x102377e5)]},
            'adapters':[hex(a) for a in sorted(o.adapters)],
            'scope':'One original maintenance iteration with controlled uniform terrain and explicit flat/scenery/building masks and neighboring plots. The ordered map node allocation/erasure and presentation are adapters. Global AOI, revisit scheduling, source unit initialization and construction are separate.'}
    (ROOT/args.output).write_text(json.dumps(result,indent=2)+'\n')
    print('Original plot maintenance:',len(cases),'cases;',[(c['name'],c['expected']['plots'][0]) for c in cases[:7]])


if __name__=='__main__':main()
