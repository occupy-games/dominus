#!/usr/bin/env python3
"""Recover original 2.4 voyage descriptors and authored introductory islands."""
import hashlib
import json
from pathlib import Path
import re
import struct

from tools.current_cards import decode_archive, rows, text
from tools.campaign import packed_map, decode_chunk

ROOT = Path(__file__).resolve().parents[1]


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def applicable(table, difficulty='easy'):
    result = []
    for row in table:
        if not row: continue
        parts = row[0].split(':')
        if len(parts)>1 and difficulty not in parts[:-1]: continue
        result.append([parts[-1], *row[1:]])
    return result


def extract(source=ROOT / 'data/godus2_4', output=ROOT / 'game/assets/original/adventures', difficulty='easy', write_catalog=True):
    from tools.voyage_lua import compile_script
    from tools.native_config import recover
    select_rows = lambda table: applicable(table,difficulty)
    suffix = '' if difficulty=='easy' else '-'+difficulty
    archive = source / 'received/godussteamrel/balance.datz'
    files = decode_archive(archive.read_bytes())
    localization = {r[0]:r[1] for r in rows(files,'gui/localization.csv') if len(r)>1}
    output.mkdir(parents=True,exist_ok=True)
    (output/'source').mkdir(exist_ok=True)
    # Raw balance tables are read as data, never Godot translation resources.
    (output/'source/.gdignore').write_text('')
    (output/'definitions').mkdir(exist_ok=True)
    packs = {p.stem.lower():p for p in (source/'stream').glob('*.pack')}
    grids, missions = {}, []
    loose_dirs={p.name.lower():p for p in (source/'stream').iterdir() if p.is_dir()}
    patches={}
    for downloaded in sorted((source/'received/godussteamrel').glob('*.datz')):
        if downloaded.name.startswith('balance') or downloaded.stat().st_size>10_000_000: continue
        downloaded_raw=downloaded.read_bytes()
        downloaded_sha=sha(downloaded_raw)
        for path,payload in decode_archive(downloaded_raw).items():
            if re.fullmatch(r'stream/[^/]+/(terrain|tree|rock|gem)_[0-7][0-7][0-7][0-7]',path):
                patches[path.lower()]=(payload,str(downloaded.relative_to(source)),downloaded_sha)
    native = recover((source/'godus.s86').read_bytes())
    defaults = {k:v['value'] for k,v in native.items()}
    for name in ['config.csv','balance/config.csv']:
        for row in rows(files,name):
            if len(row)>1 and row[0] and not row[0].startswith('#'):
                try: defaults[row[0]]=float(row[1])
                except ValueError: pass
    race_rows = rows(files,'balance/race.csv')
    power_rows = rows(files,'initialworldsetup/powerdata.csv')
    temple_rows = rows(files,'balance/templetypes.csv')
    temple_types = {r[0]:dict(zip(temple_rows[0],r)) for r in temple_rows[1:] if r and r[0]}
    generic_rows=rows(files,'balance/templegenerictypes.csv')
    generic={r[0]:dict(zip(generic_rows[0],r)) for r in generic_rows[1:] if r and r[0]}
    temple_effects={}
    for row in rows(files,'balance/templeupgrades.csv')[1:]:
        if len(row)>2 and row[1]=='AlwaysUnlocked':
            effect=re.fullmatch(r'table,\s*race,\s*(\w+),\s*m([\d.]+)',row[2])
            if effect:temple_effects[row[0]]={'stat':effect[1],'multiplier':float(effect[2])}
    tracks = {}
    for name in files:
        if name.startswith('expeditionmode/') and name.endswith('/rewarddata.csv'):
            family=name.split('/')[1]
            tracks[family]={'source':name,'sha256':sha(files[name]),'rewards':[
                {'score':int(r[0]),'id':r[1],'count':int(r[2] or 1)}
                for r in rows(files,name)[1:] if len(r)>2 and r[0].isdigit()]}
    for name in sorted(files):
        if not re.match(r'expeditionmode/[^/]+/[^/]+/info.csv$',name): continue
        directory=name.rsplit('/',1)[0]
        if any(t in directory.lower() for t in ['editor','test','/tst']): continue
        table=select_rows(rows(files,name))
        values={r[0]:r[1:] for r in table if len(r)>1}
        if 'FollowersRequired' not in values or 'BoatPos' not in values: continue
        mission_id=directory.replace('expeditionmode/','').replace('/','__')
        script=files.get(directory+'/scripts.lua',b'').decode('utf-8-sig')
        entry={'id':mission_id,'name':values.get('Name',[mission_id])[0],
               'family':directory.split('/')[1],'map':values.get('Map Prefix',[''])[0],
               'available':True,'seconds':float(values.get('Time',['0'])[0] or 0),
               'required':int(values['FollowersRequired'][0]),
               'minimum':int(values.get('Minimum followers',['5'])[0]),
               'maximum':int(values.get('Maximum followers',['30'])[0]),
               'source':directory,'source_files':{p:sha(raw) for p,raw in files.items() if p.startswith(directory+'/')},
               'unavailable_reason':''}
        try:
            program=compile_script(script)
            assigned={node[1][1] for node in program['body'] if node[0]=='assign' and node[1][0]=='var' and node[2][0]=='function'}
            program['builtins']=[call for call in program['calls'] if call not in assigned]
            pack=packs[entry['map'].lower()]
            revision_evidence={}
            if entry['map'].lower() not in grids:
                original=packed_map(pack)[0]
                merged={kind:bytearray(raw) for kind,raw in original.items()}
                for kind in ['terrain','tree','rock','gem']:
                    for cz in range(8):
                        for cx in range(8):
                            chunk=f'{kind}_{cx:02x}{cz:02x}'
                            loose=loose_dirs.get(entry['map'].lower(),source/'absent')/chunk
                            record=patches.get(f"stream/{entry['map'].lower()}/{chunk}")
                            payload=loose.read_bytes() if loose.is_file() else None
                            evidence={'source':str(loose.relative_to(source)),'sha256':sha(payload)} if payload else None
                            if record:
                                payload,member,archive_sha=record
                                evidence={'source':member+'#'+f"stream/{entry['map'].lower()}/{chunk}",'sha256':sha(payload),'archive_sha256':archive_sha}
                            if not payload: continue
                            try:decoded=decode_chunk(payload)
                            except (ValueError,struct.error):continue
                            for row in range(128):
                                begin=(cz*128+row)*1024+cx*128
                                merged[kind][begin:begin+128]=decoded[row*128:(row+1)*128]
                            revision_evidence[chunk]=evidence
                grids[entry['map'].lower()]=({k:bytes(v) for k,v in merged.items()},revision_evidence,original)
            revised,revision_evidence,original=grids[entry['map'].lower()]
            fields=original
            boat=[int(float(v)) for v in values['BoatPos'][:2]]
            dock=[int(float(v)) for v in values['DockPos'][:2]]
            temples=[]
            for row in select_rows(rows(files,directory+'/templepositions.csv'))[1:]:
                if len(row)<7 or not row[1]: continue
                temples.append({'type':row[0],'x':float(row[1]),'z':float(row[2]),
                    'height':float(row[3]) if row[3] else None,'rotation':float(row[4] or 0),
                    'uid':int(row[6] or 0),'reward':row[7] if len(row)>7 else '',
                    'build_seconds':float(row[8] or 0) if len(row)>8 else 0,
                    'builders':int(row[9] or 0) if len(row)>9 else 0,
                    'model':generic.get(temple_types.get(row[0],{}).get('type',''),{}).get('model',''),
                    'symbol':temple_types.get(row[0],{}).get('floater',''),
                    'radius':float(temple_types.get(row[0],{}).get('radius outside settlement','0') or 0)})
            destination=next(t for t in temples if t['type']=='Expedition_Goal')
            goal=[int(destination['x']),int(destination['z'])]
            if any(fields['terrain'][p[1]*1024+p[0]]<19 for p in [dock,goal]):
                fields=revised
            else: revision_evidence={}
            # The supplied archive retains two stale map references. Use only
            # identifiable supplied revisions, retaining the original CSV hash.
            alternate=None
            if entry['map'].lower()=='eventmap_05' and any(fields['terrain'][p[1]*1024+p[0]]<19 for p in [dock,goal]):
                alternate=packs.get('eventmap_05_legacy')
                entry['revision_note']='Uses the explicitly supplied legacy EventMap_05 revision at the unchanged authored coordinates.'
            if directory=='expeditionmode/event_03/ex03_map06_meteorbarrage':
                alternate=packs.get('eventmap_03a')
                entry['revision_note']='Map reference corrected by the matching event_03a/ex03a_map01_meteorbarrage info.csv: identical boat, dock, timer and goal coordinates; old CSV points at a hub.'
            if alternate:
                fields=packed_map(alternate)[0]
                pack=alternate
                revision_evidence={}
            regions=re.findall(r'LockCameraToRegion\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*\)',script)
            if not regions: raise ValueError('No original camera region')
            x,z,w,h=map(lambda v:int(float(v)),regions[0])
            x0=max(0,min(x,boat[0],dock[0],goal[0],*(int(t['x']) for t in temples))-8)
            z0=max(0,min(z,boat[1],dock[1],goal[1],*(int(t['z']) for t in temples))-8)
            width=max(x+w-x0,z+h-z0,boat[0]-x0,dock[0]-x0,goal[0]-x0,boat[1]-z0,dock[1]-z0,goal[1]-z0,
                      *(int(t['x'])-x0 for t in temples),*(int(t['z'])-z0 for t in temples))+8
            width=max(24,(width+7)//8*8)
            if width>1024 or x0+width>1024 or z0+width>1024: raise ValueError('Original island crop exceeds map extent')
            config=dict(defaults)
            races=[dict(zip(race_rows[0],r)) for r in race_rows[1:]]
            powers=[r[:] for r in power_rows]
            for row in table:
                if len(row)>2 and row[0]=='Config':
                    try:config[row[1]]=float(row[2])
                    except ValueError:config[row[1]]=row[2]
                if len(row)>4 and row[:2]==['Table','Race']:
                    index=int(row[3])
                    if index<len(races):races[index][row[2]]=row[4]
                if len(row)>4 and row[:2]==['Table','Power Data']:
                    index=int(row[3])
                    if index<len(powers) and row[2] in powers[0]:powers[index][powers[0].index(row[2])]=row[4]
            stats={}
            for index,race in enumerate(races):
                stats[race['Name']]={}
                for key,value in race.items():
                    if key=='Name':continue
                    try:stats[race['Name']][key]=float(value or 1)*(1 if index==0 else float(races[0].get(key,1) or 1))
                    except ValueError:pass
            unlocks={r[0]:r[1] for r in select_rows(rows(files,directory+'/unlocks.csv')) if len(r)>1 and r[0] and not r[0].startswith('#')}
            power_data={r[0]:{'cost':float(r[10] or config.get('belief_'+r[0].removeprefix('GodPower_'),0)),
                            'hook':r[2],'temple':r[5]} for r in powers[1:] if len(r)>10 and r[0].startswith('GodPower_')}
            objects=[]
            for row in select_rows(rows(files,directory+'/initialmapobjects.csv'))[1:]:
                if len(row)>2 and row[0] and not row[0].startswith('#') and row[1]:
                    objects.append({'type':row[0],'x':float(row[1])-x0,'z':float(row[2])-z0,
                                    'rotation':float(row[3] or 0),'depth':float(row[5] or 0) if len(row)>5 else 0,
                                    'card':row[6] if len(row)>6 else ''})
            areas=[]
            for row in select_rows(rows(files,directory+'/influence_areas.csv'))[1:]:
                if len(row)>4 and row[0] and row[1]:areas.append({'name':row[0],'x':float(row[1])-x0,'z':float(row[2])-z0,'radius':float(row[3]),'enabled':row[4]=='1'})
            for temple in temples:temple['x']-=x0;temple['z']-=z0
            n=re.search(r'(?:ex\w*_map|hallow2?map)(\d+)',directory.rsplit('/',1)[1],re.I)
            order=int(n[1]) if n else 100
            description_keys=re.findall(r'TriggerAlert\(\s*"(LOC_[^"]+)"',script)
            entry.update({'order':order,'width':width,'origin':[x0,z0],'sea_level':19,
                'boat':[boat[0]-x0,boat[1]-z0],'dock':[dock[0]-x0,dock[1]-z0],'goal':[goal[0]-x0,goal[1]-z0],
                'boat_orientation':float(values.get('BoatOrientation',['0'])[0]),'dock_orientation':float(values.get('DockOrientation',['0'])[0]),
                'goal_orientation':destination['rotation'],'belief':int(config.get('InitialBelief',0)),
                'spawn_seconds':float(config['TimeBetweenSpawnsExpedition']),
                'speed':float(races[1]['RouteSpeed']),'free_sculpt':values.get('Hide Belief Bar',['0'])[0]=='1',
                'description':'\n'.join(dict.fromkeys(text(k,localization) for k in description_keys)),
                'hints':[],'fields':{},'pack_source':str(pack.relative_to(source)),'pack_sha256':sha(pack.read_bytes()),
                'difficulty':['easy','medium','hard'].index(difficulty),'script_version':1})
            entry['stream_revisions']={chunk:evidence for chunk,evidence in revision_evidence.items()
                if x0//128<=int(chunk.split('_')[1][:2],16)<=(x0+width-1)//128
                and z0//128<=int(chunk.split('_')[1][2:],16)<=(z0+width-1)//128}
            if any(fields['terrain'][p[1]*1024+p[0]]<19 for p in [dock,goal]):
                raise ValueError('The supplied map revision has no land at the authored dock or goal; no replacement island is generated.')
            for key in ['MissionStar2Score','MissionStar3Score','MissionScoreFollowerReachedTemple','MissionScoreFollowerReachedTempleTimeMult','MissionScoreFollowerTimePower']:
                match=re.search(r'^\s*Config\("'+key+r'",\s*([\d.]+)\)',script,re.M)
                entry[key]=float(match[1]) if match else float(config.get(key,0))
            for kind in ['terrain','tree','rock','gem']:
                raw=b''.join(fields[kind][row*1024+x0:row*1024+x0+width] for row in range(z0,z0+width))
                filename=mission_id+suffix+'-'+kind+'.bin'
                (output/filename).write_bytes(raw)
                entry['fields'][kind]={'path':filename,'sha256':sha(raw)}
            definition={**entry,'program':program,'config':config,'races':stats,'power_data':power_data,
                        'unlocks':unlocks,'temples':temples,'objects':objects,'areas':areas,'temple_effects':temple_effects,
                        'script_powers':sorted(set(re.findall(r'"(GodPower_[^"]+)"',script))),
                        'texts':{k:text(k,localization) for k in set(re.findall(r'"(LOC_[^"]+)"',script))},
                        'rewards':[{'star':i,'id':values[f'Reward {i} Card Hash'][0],
                                    'count':int(values.get(f'Reward {i} ID',['1'])[0] or 1)}
                                   for i in range(1,7) if f'Reward {i} Card Hash' in values]}
            (output/'definitions'/f'{mission_id}{suffix}.json').write_text(json.dumps(definition,separators=(',',':'))+'\n')
            entry['definition']='definitions/'+mission_id+suffix+'.json'
        except (ValueError,KeyError,StopIteration) as error:
            entry['available']=False
            entry['unavailable_reason']='Source recovery incomplete: '+str(error)
        for p,raw in files.items():
            if p.startswith(directory+'/'):
                target=output/'source'/directory/Path(p).name
                target.parent.mkdir(parents=True,exist_ok=True)
                target.write_bytes(raw)
        missions.append(entry)
    missions.sort(key=lambda m:(m['family'],m.get('order',100),m['id']))
    for index,mission in enumerate(missions):
        following=next((m['id'] for m in missions[index+1:] if m['family']==mission['family'] and m['available']),'')
        if mission['available']:
            path=output/mission['definition']
            definition=json.loads(path.read_text())
            definition['next_id']=following
            path.write_text(json.dumps(definition,separators=(',',':'))+'\n')
            mission['next_id']=following
    stickers={}
    for r in rows(files,'initialworldsetup/stickerdata.csv')[1:]:
        if len(r)>7 and r[0].startswith('Sticker_'):
            stickers[r[0]]={'era':int(r[2] or 1),'internal':r[3]=='1',
                           'contributions':{r[i]:int(r[i+1]) for i in [4,6] if r[i] and r[i+1]}}
    packs_data={}
    for r in rows(files,'initialworldsetup/packdata.csv')[1:]:
        if len(r)>5 and r[0].startswith('Pack_'):
            packs_data[r[0]]=[{'id':r[i+1],'count':int(r[i])} for i in range(4,len(r)-1,2) if r[i] and r[i+1]]
    special={}
    for r in rows(files,'balance/specialcards.csv')[1:]:
        if len(r)>4 and r[0].startswith('Card_'):
            special[r[0]]={k:int(float(r[i] or 0)) for i,k in enumerate(['id','gems','belief','wheat','ore','followers']) if i and len(r)>i}
    (output/'reward-rules.json').write_text(json.dumps({'reward_tracks':tracks,'stickers':stickers,
        'packs':packs_data,'cards':special,'config':{k:v for k,v in defaults.items() if k.startswith('StickerChance_')},
        'sources':{n:sha(files[n]) for n in ['initialworldsetup/stickerdata.csv','initialworldsetup/packdata.csv','balance/specialcards.csv']},
        'native_generator':'godus.s86:1004e2ee..1004e552 selects EventSticker era weights; 1004e624.. selects useful/random stickers.'},indent=2)+'\n')
    catalog={'archive':str(archive.relative_to(source)),'archive_sha256':sha(archive.read_bytes()),
             'missions':missions,'supported_difficulty':'easy','reward_tracks':tracks,
             'conversion':'Exact square crops of original map cells. local = source - origin; Lua parsed to inert simulation instructions.',
             'native_config':{'source':'godus.s86','sha256':sha((source/'godus.s86').read_bytes()),'values':native}}
    catalog['score_evidence']={'source':'godus.s86:100f44dc..100f453f',
        'formula':'truncate(base * (1 + time_multiplier * limit * pow(remaining / limit, time_power)))',
        'intermediates':'single precision; power default 2 from native config initializer'}
    if write_catalog:(output/'catalog.json').write_text(json.dumps(catalog,indent=2)+'\n')
    return catalog


def extract_all(source=ROOT / 'data/godus2_4', output=ROOT / 'game/assets/original/adventures'):
    catalogs=[extract(source,output,difficulty,False) for difficulty in ['easy','medium','hard']]
    primary=catalogs[0]
    by_mode=[{m['id']:m for m in c['missions']} for c in catalogs]
    for mission in primary['missions']:
        mission['difficulties']=[{key:by_mode[mode][mission['id']].get(key) for key in
            ['available','unavailable_reason','definition','seconds','minimum','maximum','required','next_id']}
            for mode in range(3)]
    primary['supported_difficulty']='easy, medium, hard'
    temporary=output/'catalog.json.tmp'
    temporary.write_text(json.dumps(primary,indent=2)+'\n')
    temporary.replace(output/'catalog.json')
    return primary


if __name__ == '__main__':
    result=extract_all()
    print(f"Recovered {len(result['missions'])} original voyages; {sum(m['available'] for m in result['missions'])} source islands, three difficulties")
