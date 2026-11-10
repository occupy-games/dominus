"""Recover original building info illustrations and English labels, with provenance."""
import hashlib
import json

from tools.current_cards import decode_archive, rows, text, ROOT


def extract():
    archive = (ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    files = decode_archive(archive)
    localization = {r[0]: r[1] for r in rows(files, 'gui/localization.csv') if len(r)>1}
    records = {}
    for row in rows(files, 'balance/housevalues.csv'):
        if len(row)<=55 or not row[0].isdigit() or not row[55]: continue
        relative = 'Scaleform_Compiled/'+row[55]
        original = ROOT/'data/godus2_4'/relative
        if not original.is_file(): continue
        records[row[4]] = dict(title=text(row[1], localization), title_key=row[1],
                              illustration_source=relative, image_sha256=hashlib.sha256(original.read_bytes()).hexdigest(),
                              texture_path='res://assets/extracted/'+relative)
    for role in ['Builder', 'Farmer', 'Miner']:
        relative = 'Scaleform_Compiled/Resources/Info_Panel/Info_Settlement_'+role+'.png'
        original = ROOT/'data/godus2_4'/relative
        records['Settlement_'+role] = dict(title='', title_key='', illustration_source=relative,
            image_sha256=hashlib.sha256(original.read_bytes()).hexdigest(), texture_path='res://assets/extracted/'+relative)
    for kind in ['GodPower', 'LandExpansion']:
        relative='Scaleform_Compiled/Resources/Info_Panel/Info_Shrine_'+kind+'.png'
        original=ROOT/'data/godus2_4'/relative
        records['Shrine_'+kind]=dict(title='',title_key='',illustration_source=relative,
            image_sha256=hashlib.sha256(original.read_bytes()).hexdigest(),texture_path='res://assets/extracted/'+relative)
    temple_rows=rows(files,'balance/templetypes.csv')
    for row in temple_rows[1:]:
        temple=dict(zip(temple_rows[0],row))
        if not temple.get('name') or not temple.get('InfoPanelPic'): continue
        relative='Scaleform_Compiled/'+temple['InfoPanelPic']
        original=ROOT/'data/godus2_4'/relative
        if not original.is_file(): continue
        records['Temple_'+temple['name']]=dict(title=text(temple.get('nametext',''),localization),
            title_key=temple.get('nametext',''),illustration_source=relative,
            image_sha256=hashlib.sha256(original.read_bytes()).hexdigest(),texture_path='res://assets/extracted/'+relative)
    labels = {k: text(v, localization) for k,v in localization.items() if k.startswith((
        'LOC_ROWNAME_HOME_', 'LOC_ROWNAME_FARM_', 'LOC_ROWNAME_MINE_', 'LOC_INFO_HOUSE_',
        'LOC_INFO_FARM_', 'LOC_INFO_MINE_', 'LOC_INFO_SUB_', 'LOC_INFO_SETTLEMENT_',
        'LOC_INFO_SHRINE_', 'LOC_ROWNAME_SHRINE_', 'LOC_INFO_TIME_',
        'LOC_TemplePos_', 'LOC_TEMPLE_INFO_', 'LOC_BUTTON_SETTLEMENT_ASSIGN_BUILDERS'))}
    for key in ['LOC_INFOPANEL_STATS', 'LOC_INFO_TITLE_STATS', 'LOC_INFO_TITLE_COMPONENTS']:
        if key in localization: labels[key]=text(localization[key], localization)
    return dict(version=1, source='received/godussteamrel/balance.datz',
                source_sha256=hashlib.sha256(archive).hexdigest(),
                tables={k:hashlib.sha256(files[k]).hexdigest() for k in ['balance/housevalues.csv','balance/templetypes.csv','gui/localization.csv']},
                layout_sources={k:hashlib.sha256((ROOT/'data/godus2_4'/k).read_bytes()).hexdigest() for k in [
                    'Scaleform_Compiled/classes/OBJ_InfoPanel.as', 'Scaleform_Compiled/classes/OBJ_InfoButton.as',
                    'Scaleform_Compiled/classes/OBJ_InfoPanel_Controller.as']},
                records=records, labels=labels)


if __name__=='__main__':
    result=extract()
    for record in result['records'].values():
        source=ROOT/'data/godus2_4'/record['illustration_source']
        target=ROOT/'game'/record['texture_path'].removeprefix('res://')
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists(): target.write_bytes(source.read_bytes())
    (ROOT/'game/assets/original/ui/building-info.json').write_text(json.dumps(result, indent=2)+'\n')
    print('Original building info:', len(result['records']), 'illustration bindings')
