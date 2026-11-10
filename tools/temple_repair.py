"""Recover original temple repair gates, work constants and completion protocol."""
import hashlib
import json
import struct

from tools.current_cards import decode_archive, rows, ROOT
from tools.native_config import recover
from tools.native_scenery_oracle import NativeImage

ROUTINES=[(0x1013ce70,0x1013cecb),(0x1013ced0,0x1013cf22),(0x1013d8b0,0x1013d943),
          (0x10141204,0x101414d8),(0x10356fd0,0x10356ff5)]


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    archive=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    image=NativeImage(raw)
    native=recover(raw,['templefixerfalloff'])
    configuration={name:entry['value'] for name,entry in native.items()}
    files=decode_archive(archive)
    used={}
    for path in ['config.csv','balance/config.csv']:
        used[path]=hashlib.sha256(files[path]).hexdigest()
        for row in rows(files,path):
            if len(row)>1 and row[0] in configuration:configuration[row[0]]=float(row[1])
    constants={}
    for name,address in [('reference_effect_value',0x104a0cf4)]:
        value=image.read(address,4)
        constants[name]=dict(address=hex(address),bytes=value.hex(),value=struct.unpack('<f',value)[0])
    for name,address in [('start_hook',0x104ca73c),('complete_hook',0x104ca814),('complete_unlock',0x104ab3f0),('spending_unlock',0x104c8394)]:
        value=image.read(address,80).split(b'\0')[0]
        constants[name]=dict(address=hex(address),bytes=(value+b'\0').hex(),value=value.decode())
    rules=dict(exponent=configuration['templeFixerFalloff'],reference_effect_value=constants['reference_effect_value']['value'],
               start_hook=constants['start_hook']['value'],complete_hook=constants['complete_hook']['value'],
               complete_unlock=constants['complete_unlock']['value'],spending_unlock=constants['spending_unlock']['value'],
               dock_sound=0x5c14cfac,pit_sound=0xe88a18d3,ordinary_sound=0x35ee2088,
               ready_phase=5,working_phase=6,complete_phase=7,blocked_phase=8,temple_handle_kind=0x03000000,
               ark_finish_action=118,completion_notice=16)
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=hashlib.sha256(archive).hexdigest(),
                tables_sha256=used,native_configuration=native,configuration=configuration,constants=constants,rules=rules,
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in ROUTINES},
                scope='Original affordability helpers, repair-start routine and complete work-state block. Burial/destruction, constructors, type-specific completion visuals and full follower dispatch remain separate ports.')


if __name__=='__main__':
    data=extract()
    (ROOT/'game/assets/original/campaign/temple-repair.json').write_text(json.dumps(data,indent=2)+'\n')
    print('Original temple repair exponent:',data['rules']['exponent'])
