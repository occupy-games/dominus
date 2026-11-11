"""Recover Holy Forest's desktop balance, upgrade and tutorial records."""
import hashlib
import json
from pathlib import Path
import re
import struct

from tools.current_cards import decode_archive, rows, text
from tools.native_config import recover
from tools.native_scenery_oracle import ROOT, NativeImage


def extract(output):
    source = ROOT / 'data/godus2_4'
    raw = (source / 'godus.s86').read_bytes()
    archive = (source / 'received/godussteamrel/balance.datz').read_bytes()
    files = decode_archive(archive)
    image = NativeImage(raw)
    config_names = {
        'cost': 'CostPerGodSeed', 'cost_increment': 'CostIncreasePerTree',
        'emerge_seconds': 'NewTreeEmergeTime', 'rise': 'NewTreeRiseOn',
        'sink_distance': 'SeedSinkDistance', 'happiness_multiplier': 'HappinessMultiplier',
    }
    native = recover(raw, ['seed', 'tree', 'happiness'])
    desktop = {row[0]: row[1] for table in ('config.csv', 'balance/config.csv')
               for row in rows(files, table) if len(row) > 1}
    rules = {key: float(desktop.get(name, native[name]['value'])) for key, name in config_names.items()}
    rules['sea_height'], = struct.unpack('<f', image.read(0x104ad010, 4))
    scope = 'initialworldsetup6'
    card = 'Card_Adv_GodSeed_1'
    power = 'GodPower_GodSeed'
    population, = [int(row[0]) for row in rows(files, f'{scope}/populationlevels.csv') if len(row) > 1 and row[1] == card]
    unlocks = {row[0]: row[1] for row in rows(files, f'{scope}/unlocks.csv') if len(row) > 1}
    power_row, = [row for row in rows(files, 'initialworldsetup/powerdata.csv') if row and row[0] == power]
    if unlocks[power] != card or power_row[2] != 'GODSEED' or power_row[8] != 'INSTANT':
        raise ValueError('Holy Forest discovery or cast changed')
    rules.update(card=card, power=power, population=population)
    happiness = {row[1]: [float(row[2]), float(row[3])] for row in rows(files, 'balance/happiness.csv')
                 if len(row) > 3 and row[1].startswith(('Plant tree inside', 'Plant tree outside'))}
    rules['happiness_near'] = happiness['Plant tree inside radius of abode/Settlement']
    rules['happiness_far'] = happiness['Plant tree outside radius of abode/Settlement']
    localization = {row[0]: row[1] for row in rows(files, 'gui/localization.csv') if len(row) > 1}
    modifiers = {row[0]: [] for row in rows(files, 'balance/balanceunlockmodifier.csv') if len(row) > 1}
    for row in rows(files, 'balance/balanceunlockmodifier.csv'):
        if len(row) > 1:
            modifiers[row[0]].append(row[1])
    rules['upgrades'] = []
    for index, role in enumerate(('farm', 'mine'), 1):
        unlock = f'Upgrade_{power}_{index}'
        upgrade_id = f'LvlUp_{power}_{index}'
        row, = [r for r in rows(files, 'gui/powerupgradedata.csv') if len(r) >= 9 and r[1] == upgrade_id]
        if (row[0] != 'Card_' + power or row[2] != 'AlwaysUnlocked' or row[4:6] != ['GEMS', 'UPGRADE']
                or unlocks[unlock] != upgrade_id or f'Table,Environment Buffs,{role},6,1' not in modifiers[unlock]):
            raise ValueError('Unsupported Holy Forest upgrade')
        rules['upgrades'].append(dict(id=upgrade_id, unlock=unlock, role=role, cost=int(row[3]), currency=row[4],
                                      button=text(row[6], localization), title=text(row[7], localization),
                                      description=text(row[8], localization)))
    script = files[f'{scope}/scripts.lua'].decode('utf-8-sig', errors='replace')
    tutorial = script.split('uiTable.GodSeed =', 1)[1].split('tutorialTable.GodSeed =', 1)[0]
    if any(key not in tutorial for key in ('LOC_GSeedTUT_01', 'LOC_GSeedTUT_06', 'CARD_TIP_POS')):
        raise ValueError('Missing Holy Forest tutorial bindings')
    anchor = re.search(rb'CARD_TIP_POS\s*=\s*\{([\d.]+),\s*([\d.]+)\}', files['scripts.lua'])
    if not anchor:
        raise ValueError('Missing original card tip position')
    rules['messages'] = {
        '5701': dict(group='GodSeed', source_id=1, strType='Gold', stemType=2,
                     pos2d={'1': float(anchor[1]), '2': float(anchor[2])},
                     key='LOC_GSeedTUT_01', text=text('LOC_GSeedTUT_01', localization)),
        '5702': dict(group='GodSeed', source_id=2, strType='Alert', key='LOC_GSeedTUT_06',
                     text=text('LOC_GSeedTUT_06', localization)),
    }
    vfx_path = 'VFX/Scripts/GOD_GodSeed_Impact.txt'
    effect = (source / vfx_path).read_bytes()
    if b'PLAYSOUND=GodSeed' not in effect:
        raise ValueError('Missing Holy Forest planting sound')
    rules['sound'] = 'PLAYSOUND_GODSEED'
    inputs = ('config.csv', 'balance/config.csv', 'balance/happiness.csv', 'balance/environmentbuffs.csv',
              'balance/balanceunlockmodifier.csv', 'gui/powerupgradedata.csv', 'gui/localization.csv',
              'initialworldsetup/powerdata.csv', f'{scope}/populationlevels.csv', f'{scope}/unlocks.csv',
              f'{scope}/scripts.lua', 'scripts.lua')
    result = dict(rules=rules, source_sha256=hashlib.sha256(archive).hexdigest(),
                  executable_sha256=hashlib.sha256(raw).hexdigest(),
                  tables_sha256={key: hashlib.sha256(files[key]).hexdigest() for key in inputs},
                  effect_source=vfx_path, effect_sha256=hashlib.sha256(effect).hexdigest(),
                  native_configuration={name: native[name] for name in config_names.values()},
                  native_routines={hex(a): image.read(a, b-a).hex() for a, b in (
                      (0x10087880, 0x10087925), (0x10087a00, 0x10087ae0),
                      (0x10087b50, 0x10087bd0), (0x10087db0, 0x10087df0),
                      (0x10087fd0, 0x100880f1), (0x10154250, 0x1015437d),
                      (0x10157259, 0x101572d2))})
    Path(output).write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    content = extract(ROOT / 'game/assets/original/campaign/god-seed.json')
    print('Holy Forest:', content['rules']['population'], 'followers,', content['rules']['cost'], 'belief')
