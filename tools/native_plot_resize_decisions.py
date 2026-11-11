"""Compile the original finite plot-resize branch kernels into plain rule tables.

Inputs are native predicate results, not terrain approximations. The grow and
repair choices execute every Boolean combination in the supplied executable.
Runtime needs these small source-derived tables, never a CPU emulator.
"""
import argparse
from pathlib import Path

from tools.native_scenery_oracle import Oracle, ROOT
from tools.plot_resize import GROW_SLOTS, REPAIR_SLOTS, write_tables


class DecisionOracle(Oracle):
    def configure_decisions(self):
        self.adapters={0x10237580:lambda:self.return_integer(), # footprint registration, after the decision
                       0x100f1b20:lambda:self.return_integer(pop=12), # spatial render registration
                       0x10254390:lambda:self.return_integer(),0x102545c0:lambda:self.return_integer()}
        self.handles=[self.cpu.hook_add(self.hook_kind,self.hook,begin=a,end=a) for a in self.adapters]

    def evaluate(self,kind,mask,maximum=6):
        frame=self.STACK+0x80000
        self.cpu.mem_write(frame-0x2000,bytes(0x2000))
        self.cpu.mem_write(self.POOL,bytes(0x74))
        self.set_integer(self.POOL+4,4)
        self.set_float(self.POOL+8,160.)
        self.set_float(self.POOL+12,120.)
        self.set_float(self.POOL+16,6.)
        self.set_integer(frame-0x20,self.POOL)
        self.set_integer(frame-0x2c,self.POOL+4)
        self.set_integer(frame-0x40,maximum)
        slots=GROW_SLOTS if kind=='grow' else REPAIR_SLOTS
        for i,slot in enumerate(slots):self.set_integer(frame+slot,int(bool(mask&(1<<i))))
        self.cpu.reg_write(self.regs.UC_X86_REG_EBX,0 if kind=='grow' else self.POOL)
        self.cpu.reg_write(self.regs.UC_X86_REG_ESP,frame-0x3000)
        self.cpu.reg_write(self.regs.UC_X86_REG_EBP,frame)
        self.cpu.mem_write(self.SCRATCH+0x700,b'\xdb\xe3')
        self.cpu.emu_start(self.SCRATCH+0x700,self.SCRATCH+0x702)
        start,end=(0x102383b4,0x102397ed) if kind=='grow' else (0x10239302,0x1023971b)
        self.cpu.emu_start(start,end,count=100000)
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=end:raise ValueError('Original resize decision did not finish')
        size=self.integer(self.POOL+4)
        dx=int(self.float(self.POOL+8)-160.)
        dz=int(self.float(self.POOL+12)-120.)
        delta=size-4
        if dx not in [-1,0,1] or dz not in [-1,0,1] or delta not in [-4,-2,-1,0,1,2]:
            raise ValueError('Unknown original resize action')
        # Shared 1-byte action format: dx+1, dz+1, then size operation.
        mode=([0,1,2].index(delta) if kind=='grow' else [-2,-1,0,-4].index(delta))
        return (dx+1)|((dz+1)<<2)|(mode<<4)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default=str(ROOT/'game/assets/original/campaign'))
    args=parser.parse_args()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    oracle=DecisionOracle(raw)
    oracle.configure_decisions()
    growth=bytes(oracle.evaluate('grow',mask,maximum) for maximum in [4,5,6] for mask in range(256))
    repair=bytes(oracle.evaluate('repair',mask) for mask in range(4096))
    write_tables(oracle.image,Path(args.output),growth,repair,oracle.touched)
    print('Original plot resize decisions:',len(growth),'growth,',len(repair),'repair; actions',sorted(set(growth)),sorted(set(repair)))


if __name__=='__main__':main()
