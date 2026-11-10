"""Compare original building work arithmetic without starting the game.

The optional x86 emulator runs the supplied construction block and native powf,
with plain count/skill arrays and a resolved unit row. Host services are absent.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from tools.native_scenery_oracle import Oracle, ROOT


class ConstructionOracle(Oracle):
    def configure_building(self):
        self.configure(b'',b'',b'',[])
        self.house=self.POOL
        self.unit=self.SCRATCH+0x3000
        self.set_integer(0x10f928e8,self.SCRATCH+0x4000)
        self.set_integer(self.SCRATCH+0x4000,self.house)
        self.set_float(self.house+0x14,-1) # No per-house build-time override.
        self.adapters[0x100b7580]=lambda:self.return_integer(self.unit)
        self.adapters[0x10245d30]=lambda:self.return_integer() # source Lua event delivery
        for address in [0x100b7580,0x10245d30]:
            self.handles.append(self.cpu.hook_add(self.hook_kind,self.hook,begin=address,end=address))

    def advance_work(self,count,contributors,skill_sum,exponent,delta,progress=0,rate=1):
        self.set_integer(0x10f928ec,count)
        self.set_integer(0x10f968ec,contributors)
        self.set_float(0x10f9a8ec,skill_sum)
        self.set_float(0x10fcd81c,rate)
        self.set_float(self.unit+0x98,exponent)
        self.set_float(self.unit+0x4c,7.5)
        self.set_float(self.house+0x38,progress)
        # Enter the actual building-state case after its unrelated scene work.
        # Stack/local ownership is exactly the parent routine's x86 frame.
        frame=self.STACK+0x80000
        self.set_float(frame+8,delta)
        self.cpu.reg_write(self.regs.UC_X86_REG_ESP,frame-0x200)
        self.cpu.reg_write(self.regs.UC_X86_REG_EBP,frame)
        self.cpu.reg_write(self.regs.UC_X86_REG_ESI,self.house)
        self.cpu.reg_write(self.regs.UC_X86_REG_EDI,0)
        self.cpu.reg_write(self.regs.UC_X86_REG_EBX,1)
        # x87 is initialized by a separate two-instruction scratch harness.
        self.cpu.mem_write(self.SCRATCH+0x700,b'\xdb\xe3')
        self.cpu.emu_start(self.SCRATCH+0x700,self.SCRATCH+0x702)
        try: self.cpu.emu_start(0x100bdaa2,0x100bdbc6,count=1000000)
        except Exception as error:
            raise ValueError('Original construction instruction failed at '+hex(self.cpu.reg_read(self.regs.UC_X86_REG_EIP))) from error
        if self.cpu.reg_read(self.regs.UC_X86_REG_EIP)!=0x100bdbc6:
            raise ValueError('Original construction work block did not finish')
        return self.float(self.house+0x38)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'game/tests/fixtures/source_construction.json')
    args=parser.parse_args()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    oracle=ConstructionOracle(raw)
    oracle.configure_building()
    cases=[]
    for count,contributors,skill_sum,exponent,delta,progress,rate in [
            (0,0,0,.3,.1,0,1),(1,1,1,.3,.1,0,1),(2,2,2,.3,.1,0,1),
            (3,3,3,.5,.1,0,1),(4,4,4,.5,.1,0,1),(8,8,8,.7,.1,0,1),
            (2,2,3,.3,.1,0,1),(1,2,3,.3,.1,0,1),(2,4,3,.3,.1,2,1),
            (2,2,2,.3,.1,2,1.5),(5,5,5,0,.1,0,1),(5,5,5,1,.1,0,1)]:
        values=dict(count=count,contributors=contributors,skill_sum=skill_sum,exponent=exponent,
                    delta=delta,progress=progress,rate=rate)
        values['result']=oracle.advance_work(**values)
        cases.append(values)
    result={'executable_sha256':hashlib.sha256(raw).hexdigest(),
            'native_routines':{hex(start):oracle.image.read(start,end-start).hex()
                               for start,end in [(0x100bdaa2,0x100bdbc6),(0x10079210,0x1007923a),
                                                 (0x100b7430,0x100b745a),(0x10034650,0x1003467e),
                                                 (0x100b7e80,0x100b7ef5),(0x100b8cd0,0x100b8d5d),
                                                 (0x10356fd0,0x10356ff5)]},
            'adapters':[hex(v) for v in sorted(oracle.touched)],'cases':cases,
            'scope':'Construction work accumulator only. Counts and skill aggregates are explicit inputs; follower decisions, repair, completions and scenes are not emulated.'}
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print('Original construction work:',len(cases),'cases;',[(c['count'],c['exponent'],c['result']) for c in cases[:6]])


if __name__=='__main__': main()
