"""Recover native tree terrain-response and scale configuration, with provenance."""
import hashlib
import json
from pathlib import Path
import struct

from tools.current_cards import decode_archive, rows
from tools.native_config import recover
from tools.native_scenery_oracle import ROOT, NativeImage


def extract(output=None):
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    archive=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    image=NativeImage(raw)
    names={'vertical_scale':('TreeVerticalScale',0x105d91fc),
           'encouragement_scale':('TreeMaxEncouragementScale',0x105d9200),
           'duration':('treeAnimationTime',0x105d920c),'minimum_scale':('TreeMinScale',0x105d9210)}
    evidence=recover(raw,['tree'])
    files=decode_archive(archive)
    config={r[0]:r[1] for path in ['config.csv','balance/config.csv'] for r in rows(files,path) if len(r)>1}
    values={}
    selected={}
    for key,(name,address) in names.items():
        row=evidence[name]
        if row['data']!=hex(address): raise ValueError('Unknown tree configuration slot')
        values[key]=float(config.get(name,row['value']))
        selected[name]=row
    result=dict(values,source_sha256=hashlib.sha256(archive).hexdigest(),executable_sha256=hashlib.sha256(raw).hexdigest(),
                sea_height=struct.unpack('<f',image.read(0x104ad010,4))[0],configuration_evidence=selected,
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in [
                    (0x10260e90,0x10261557),(0x10156800,0x101568e6),(0x10156ae0,0x10156c48),
                    (0x10155f20,0x10156133),(0x1025ffde,0x1025fff4),(0x1026016f,0x1026018f),
                    (0x101570a5,0x101570d6)]})
    if output: Path(output).write_text(json.dumps(result,indent=2)+'\n')
    return result


if __name__=='__main__':
    print('Original tree response:',extract(ROOT/'game/assets/original/campaign/tree-response.json')['duration'],'seconds')
