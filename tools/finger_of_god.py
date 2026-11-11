"""Recover desktop Finger of God rules from the shipped tables and PE image."""
import hashlib
import json
import struct
from pathlib import Path

from tools.current_cards import decode_archive, rows, text
from tools.native_config import recover
from tools.native_scenery_oracle import ROOT, NativeImage
from tools.original_assets import iw_hash


def extract(source, output):
    source = Path(source)
    executable = (source / 'godus.s86').read_bytes()
    archive = (source / 'received/godussteamrel/balance.datz').read_bytes()
    image = NativeImage(executable)
    files = decode_archive(archive)
    scope = 'initialworldsetup6'
    card = 'Card_Adv_FingerOfGod_1'
    power = 'GodPower_FingerOfGod'
    population, = [int(row[0]) for row in rows(files, f'{scope}/populationlevels.csv') if row[1:2] == [card]]
    advance, = [row for row in rows(files, f'{scope}/carddata.csv') if row[:1] == [card]]
    unlock, = [row for row in rows(files, f'{scope}/unlocks.csv') if row[:1] == [power]]
    cast, = [row for row in rows(files, 'initialworldsetup/powerdata.csv') if row[:1] == [power]]
    if advance[2:4] != ['ADVANCE', 'PROGRESS'] or advance[7:9] != ['FAITH', '0'] or unlock[1] != card:
        raise ValueError('Unexpected Finger of God discovery or research requirement')
    if cast[2:5] != ['FINGEROFGOD', '1', 'MIRACLE'] or cast[8:11] != ['INSTANT', '', '0']:
        raise ValueError('Unexpected Finger of God cast type or activation fee')
    desktop = {row[0]: row[1] for name in ('config.csv', 'balance/config.csv') for row in rows(files, name) if len(row) > 1}
    native = recover(executable, ['godfinger', 'fingerofgod', 'finger_of_god', 'burning_per_sec', 'happinessmultiplier',
                                  'treeburntint', 'tree_fire_imposter_mindark'])
    parameters = {
        'duration': 'FingerOfGodLength',
        'radius': 'GodFingerEffectRadius',
        'settlement_taps': 'SettCompGodFingerTapsToDestroy',
        'settlement_reset': 'SettCompGodFingerTapReset',
        'monument_taps': 'GodFingerDifficultTapsToDestroy',
        'monument_reset': 'GodFingerDifficultTapReset',
        'rock_raise_radius': 'FINGER_OF_GOD_ROCK_LAND_RAISE_RADIUS',
        'rock_raise_height': 'FINGER_OF_GOD_ROCK_LAND_RAISE_HEIGHT',
        'burn_rate': 'BURNING_PER_SEC',
        'burn_tint': 'TreeBurnTintFac',
        'burn_imposter_scale': 'TREE_FIRE_IMPOSTER_MINDARK',
        'happiness_multiplier': 'HappinessMultiplier',
        'rest_height': 'GodFingerRestHeight',
        'rotation_z': 'GodFingerRotationZ',
        'rotation_x': 'GodFingerRotationX',
        'target_offset_x': 'GodFingerTargetOffsetX',
        'target_offset_z': 'GodFingerTargetOffsetY',
        'acceleration': 'GodFingerDownAccell',
        'max_velocity': 'GodFingerMaxVel',
    }
    costs = {key: f'FingerOfGod{suffix}Cost' for key, suffix in (
        ('home', 'House'), ('settlement', 'Settlement'), ('tree', 'Tree'), ('rock', 'Rock'),
        ('follower', 'Follower'), ('flick', 'FollowerFlick'))}

    def value(name):
        return float(desktop.get(name, native[name]['value']))

    rules = {key: value(name) for key, name in parameters.items()}
    rules['costs'] = {key: int(value(name)) for key, name in costs.items()}
    rules['cost_keys'] = costs
    rules.update(card=card, power=power, population=population, activation_cost=int(cast[10]),
                 sea_height=struct.unpack('<f', image.read(0x104ad010, 4))[0],
                 hover_height=struct.unpack('<f', image.read(0x105ac524, 4))[0],
                 surface_offset=struct.unpack('<d', image.read(0x104a3328, 8))[0],
                 model_scale=struct.unpack('<d', image.read(0x104a0ce0, 8))[0],
                 rock_raise_threshold=struct.unpack('<d', image.read(0x104b0530, 8))[0],
                 sound='Finger of God impact')
    if (desktop['ArmPowerFingerOfGod'] != '1'
            or image.read(0x101bfebe, 5) != b'\xb9\x78\x3e\xa7\x10'
            or image.read(0x100860dd, 5) != b'\x68\xa8\x9f\x3d\xa2'):
        raise ValueError('Missing Finger of God arming or impact dispatch')
    model = 'god_finger.group.bin'
    rules['model'] = f'{model}:{iw_hash("god_finger"):08x}'
    happiness = {row[1]: row[2:4] for row in rows(files, 'balance/happiness.csv') if len(row) >= 4}
    labels = {
        'follower': 'Follower Death by Finger',
        'flick': 'Follower Flick by Finger',
        'home': 'Finger Of God Destroyed Abode',
        'settlement': 'Finger Of God Destroyed Settlement',
        'gift': 'Finger Of God Destroyed Gift',
        'tree_near': 'Finger Of God Set on fire tree inside radius of abode/Settlement',
        'tree_far': 'Finger Of God Set on fire tree outside radius of abode/Settlement',
    }
    rules['happiness'] = {key: [float(amount) for amount in happiness[label]] for key, label in labels.items()}
    localization = {row[0]: row[1] for row in rows(files, 'gui/localization.csv') if len(row) > 1}
    tutorial = files[f'{scope}/scripts.lua'].decode('utf-8-sig', errors='replace')
    if 'messages = {"LOC_FingerTUT_01", "LOC_FingerTUT_02"}' not in tutorial.expandtabs(1):
        raise ValueError('Missing Finger of God tutorial')
    rules['messages'] = {
        '5901': dict(group='Finger', strType='Gold', gui='PowerSelectCard', gui_info='Card_' + power,
                     text=text('LOC_FingerTUT_01', localization)),
        '5902': dict(group='Finger', strType='Gold', gui='BeliefActivePower', offset={'1': 6, '2': 3},
                     text=text('LOC_FingerTUT_02', localization)),
    }
    inputs = ('config.csv', 'balance/config.csv', 'balance/happiness.csv', 'gui/localization.csv',
              'initialworldsetup/powerdata.csv', f'{scope}/populationlevels.csv', f'{scope}/carddata.csv',
              f'{scope}/unlocks.csv', f'{scope}/scripts.lua')
    result = dict(rules=rules, source_sha256=hashlib.sha256(archive).hexdigest(),
                  executable_sha256=hashlib.sha256(executable).hexdigest(),
                  model_sha256=hashlib.sha256((source / model).read_bytes()).hexdigest(),
                  tables_sha256={key: hashlib.sha256(files[key]).hexdigest() for key in inputs},
                  native_configuration={name: native[name] for name in (*parameters.values(), *costs.values())},
                  native_routines=dict(arm='0x101bfebc', minimum='0x10026070', impact='0x10085ea0',
                                       contact='0x10084cc0', frame='0x10086260', rock_land='0x10142e50'))
    Path(output).write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    result = extract(ROOT / 'data/godus2_4', ROOT / 'game/assets/original/campaign/finger-of-god.json')
    print('Finger of God:', result['rules']['population'], 'followers,', result['rules']['duration'], 'seconds')
