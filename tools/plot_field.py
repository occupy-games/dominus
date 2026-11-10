"""Losslessly recover the supplied Homeworld plot-rotation byte field."""
from collections import Counter
import hashlib
import json

from tools.campaign import packed_map
from tools.native_scenery_oracle import ROOT


def extract():
    path=ROOT/'data/godus2_4/stream/Homeworld6.pack'
    fields,*_=packed_map(path)
    raw=fields['plotrot']
    default=Counter(raw).most_common(1)[0][0]
    return dict(version=1,source='stream/Homeworld6.pack',pack_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                width=1024,field='plotrot',sha256=hashlib.sha256(raw).hexdigest(),default=default,
                overrides=[[index,value] for index,value in enumerate(raw) if value!=default])


if __name__=='__main__':
    data=extract()
    (ROOT/'game/assets/original/campaign/plot-field.json').write_text(json.dumps(data,indent=2)+'\n')
    print('Original plot field:',data['default'],'default,',len(data['overrides']),'overrides')
