"""Original registry binding followed by the original complete reward pipeline.

The registry and reward kernels run on separate bounded CPU instances. Detached
records and all inventory tables transfer between them; neither kernel's game
rules are replaced. This proves composition across that explicit data boundary,
not outer application startup or complete campaign progression.
"""
import copy
import json

from tools.native_availability_oracle import empty
from tools.native_reward_catalog_oracle import CatalogOracle
from tools.native_selected_rewards_oracle import SelectedRewardsOracle
from tools.reward_catalog import extract as catalog_content
from tools.card_research import extract as research_content
from tools.reward_queue import extract as queue_content
from tools.sticker_selection import extract as selection_content
from tools.reward_dispatch import extract as dispatch_content,key
from tools.native_scenery_oracle import ROOT


def cases(catalog,queue):
    source=dict(records=dict(packs=catalog['packs'],stickers=catalog['stickers'],cards=catalog['scopes']['initialworldsetup6']['cards']),
                details=catalog['details'],rules=catalog['rules'])
    examples=[]
    def add(name,steps):
        records=copy.deepcopy(source['records'])
        records.update(special=queue['special'],stories=[])
        examples.append(dict(name=name,source=copy.deepcopy(source),records=records,availability=empty(),
                             words=[0,32767,1,16384,32760,8192,25000,67],era=2,steps=steps))
    for row in source['records']['cards']:
        if row['type']!=2:continue
        steps=[]
        for i in range(3):steps.extend([dict(action='dispatch',reward=row['id'],flags=3),dict(action='consume')])
        add('advance_'+row['source_id'],steps)
    for row in source['records']['packs']:
        count=sum(max(0,s['count']) for s in row['slots'])
        steps=[dict(action='temple',reward=row['id'])]
        steps.extend([dict(action='take',kind=k) for k in [0,1]]*count)
        steps.extend([dict(action='consume')]*(count+1))
        add('pack_'+str(row['id']),steps)
    return examples


def main():
    catalog=catalog_content();queue=queue_content();selection=selection_content();dispatch=dispatch_content()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    registry=CatalogOracle(raw);registry.configure_catalog()
    oracle=SelectedRewardsOracle(raw);oracle.configure_selected(queue,selection)
    examples=cases(catalog,queue)
    for case in examples:
        registry.load_catalog(dict(records=case['records'],details=case['source']['details'],availability=case['availability']))
        bound=registry.bind()
        case['prepared']=copy.deepcopy(bound)
        configured=dict(case,records=bound['records'],availability=bound['availability'])
        oracle.load_selected(configured)
        case['states']=[oracle.advance_researched(step) for step in case['steps']]
    output=dict(executable_sha256=catalog['executable_sha256'],source_sha256=catalog['source_sha256'],
                native_routines={**catalog['native_routines'],**queue['native_routines'],**selection['native_routines'],**dispatch['native_routines'],**research_content()['native_routines']},
                registry_adapters=[hex(a) for a in sorted(registry.adapters)],reward_adapters=[hex(a) for a in sorted(oracle.adapters)],
                cases=examples,scope=__doc__.strip())
    (ROOT/'game/tests/fixtures/source_registered_rewards.json').write_text(json.dumps(output,separators=(',',':'))+'\n')
    print('Original registered rewards:',len(examples),'cases,',sum(len(c['steps']) for c in examples),'transitions')


if __name__=='__main__':main()
