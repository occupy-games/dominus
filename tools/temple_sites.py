"""Recover authored campaign temple sites and their original type/model chains."""
import hashlib
import json

from tools.current_cards import decode_archive, rows, ROOT


def number(row,key,default=0):
    value=row.get(key,'')
    return float(value) if value else default


def records(files,path):
    table=rows(files,path)
    return [dict(zip(table[0],row)) for row in table[1:] if row and row[0] and not row[0].startswith('#')]


def extract():
    raw=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    files=decode_archive(raw)
    type_path='balance/templetypes.csv'
    generic_path='balance/templegenerictypes.csv'
    types={row['name']:row for row in records(files,type_path)}
    generic={row['name']:row for row in records(files,generic_path)}
    used={path:hashlib.sha256(files[path]).hexdigest() for path in [type_path,generic_path]}
    scopes={}
    ambiguous={}
    for scope in ['initialworldsetup']+[f'initialworldsetup{i}' for i in range(2,8)]:
        path=scope+'/templepositions.csv'
        used[path]=hashlib.sha256(files[path]).hexdigest()
        sites=[]
        for row in records(files,path):
            identity=row.get('uID','')
            if not identity or not identity.isdigit():continue
            type=types.get(row['Type'],{})
            shape=generic.get(type.get('type',''),{})
            site=dict(id=identity,type=row['Type'],x=number(row,'x'),z=number(row,'y'),
                      source_height=number(row,'height') if row.get('height') else None,
                      rotation=number(row,'rotation'),mission=int(number(row,'mission')),
                      card=row.get('reward',''),build_ticks=round(number(row,'timeToBuild')*10),
                      build_capacity=int(number(row,'numberOfBuilders',number(type,'number of builders'))),
                      food_cost=int(number(row,'foodCost')),ore_cost=int(number(row,'oreCost')),
                      build_priority=number(type,'RepairPriority'),generic_type=type.get('type',''),model=shape.get('model',''),
                      width=number(shape,'w'),depth=number(shape,'h'),nav_size=number(shape,'NavSize'),
                      title=row.get('title','') or type.get('nametext',''),description=row.get('desc','') or type.get('description',''),
                      info_image=type.get('InfoPanelPic',''),info_description=type.get('InfoPanelDescrip',''),
                      source_table=path,source_center=True)
            sites.append(site)
        repeated=sorted({site['id'] for site in sites if sum(other['id']==site['id'] for other in sites)>1})
        if repeated:ambiguous[scope]=repeated
        scopes[scope]=sites
    return dict(version=1,source_sha256=hashlib.sha256(raw).hexdigest(),tables_sha256=used,scopes=scopes,ambiguous_ids=ambiguous,
                scope='Original authored placements and type/generic fields. This is not a port of each temple type behavior; blank source model mappings remain unavailable.')


if __name__=='__main__':
    content=extract()
    (ROOT/'game/assets/original/campaign/temple-sites.json').write_text(json.dumps(content,indent=2)+'\n')
    print('Original temple sites:',sum(len(v) for v in content['scopes'].values()),'in',len(content['scopes']),'campaign scopes')
