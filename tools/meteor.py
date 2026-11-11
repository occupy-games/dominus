"""Read Meteor Strike's authored unlock, upgrades and native motion parameters."""
import hashlib
from pathlib import PurePosixPath
import re
import struct

from tools.current_cards import rows, text
from tools.voyage_lua import CompileError


def visual_rules(source, image, config):
    def path_at(address):
        return image.read(address, 96).split(b'\0', 1)[0].decode('ascii')

    def asset(path):
        return {'path': path, 'sha256': hashlib.sha256((source / path).read_bytes()).hexdigest()}

    streak = asset(path_at(0x104d86f4))
    streak.update(length=config.get('MeteorLength', struct.unpack('<f', image.read(0x105c141c, 4))[0]),
                  head_ratio=config.get('MeteorHeadRatio', struct.unpack('<f', image.read(0x105c1420, 4))[0]),
                  head_v=struct.unpack('<f', image.read(0x104c13c0, 4))[0])
    script = asset(path_at(0x104d7d18))
    program = (source / script['path']).read_text()
    if 'FLARE.alphaType=A' not in program or 'FLARE.worldspaceSize=1' not in program:
        raise CompileError('Unexpected original Meteor Strike flare mode')
    filename = PurePosixPath(re.search(r'^TEX=(.+)$', program, re.M)[1]).name
    alpha = re.search(r'^FLARE.alphaGrad=(.+)$', program, re.M)[1]
    flare = asset('VFX/Textures/' + filename)
    flare.update(source=script, size=float(re.search(r'^FLARE.size=(.+)$', program, re.M)[1]),
                 color=re.search(r'^FLARE.colour=x([0-9a-fA-F]{6})$', program, re.M)[1],
                 alpha=[[float(time), float(value)] for time, value in re.findall(r'@([\d.]+):([\d.]+)', alpha)],
                 lifetime=float(re.search(r'^@([\d.]+):STOPFLARE=impactFlare$', program, re.M)[1]))
    return {'streak': streak, 'flare': flare}


def extract(source, files, image, config, levels, unlocks, power_table, localization):
    card = 'Card_Adv_MeteorStrike_1'
    power = 'GodPower_MeteorStrike'
    level = next(row for row in levels if row[1] == card)
    cast = next(row for row in rows(files, power_table) if row[0] == power)
    if cast[2] != 'METEOR' or cast[4] != 'MIRACLE' or cast[8] != 'INSTANT' or not any(
            row[:2] == [power, card] for row in unlocks):
        raise CompileError('Unexpected original Meteor Strike unlock or power type')

    native = {
        'swipe': (0x1008b943, 'e838b80600'),
        'debit': (0x1008b968, 'e863a8f9ff'),
        'crater': (0x100f8605, 'e876b40400'),
        'blight': (0x100f8633, 'e8b8e9ffff'),
        'damage': (0x100f89f4, 'e80745f7ff'),
    }
    for name, (address, opcode) in native.items():
        expected = bytes.fromhex(opcode)
        if image.read(address, len(expected)) != expected:
            raise CompileError(f'Unexpected Meteor Strike {name} instruction at {address:#x}')

    tunables = {
        'swipe_min': ('MeteorMinSwipeDist', 0x105adf60),
        'swipe_max': ('MeteorMaxSwipeDist', 0x105adf64),
        'speed_from_length': ('MeteorSwipeSpeedFromDragLen', 0x105adf4c),
        'min_time': ('MeteorSwipeMinTime', 0x105adf50),
        'max_time': ('MeteorSwipeMaxTime', 0x105adf54),
        'min_speed': ('MeteorMinSpeed', 0x105adf58),
        'max_speed': ('MeteorMaxSpeed', 0x105adf5c),
        'distance': ('MeteorInitialDistance', 0x105c0fdc),
        'strength': ('MeteorStrengthFac', 0x105c13f4),
        'crater_radius': ('MeteorBlastRadius', 0x105c1404),
        'crater_depth': ('MeteorBlastStrength', 0x105c1408),
        'blight': ('MeteorBlightAmount', 0x105c1410),
        'blast_speed': ('MeteorBlastSpeed', 0x105c13bc),
        'blast_max': ('MeteorMaxBlastDistance', 0x105c13b8),
        'blast_size_start': ('MeteorBlastSizeStart', 0x105c13c0),
        'blast_size_end': ('MeteorBlastSizeEnd', 0x105c13c4),
        'house_radius': ('MeteorHouseDestroyRadius', 0x105c13f0),
        'damage': ('MeteorDamageMultiplier', 0x105c13f8),
        'settlement_taps': ('SettMeteorsToDestroy', 0x105c13fc),
        'settlement_reset': ('SettMeteorsTimeReset', 0x105c1400),
    }
    rules = {key: config.get(name, struct.unpack('<f', image.read(address, 4))[0])
             for key, (name, address) in tunables.items()}
    for key, address in {
        'angle_scale': 0x104b0d38, 'angle_min': 0x104b0d30, 'angle_max': 0x104a2348,
        'radians_per_degree': 0x104a0d98, 'speed_scale': 0x104aaef0,
        'depth_scale': 0x104c13b0, 'radius_scale': 0x104c1470,
        'ground_skin': 0x104a0c30, 'impact_drop': 0x104a0d40,
        'water_slowdown': 0x104a0d48, 'drag': 0x104a6d68, 'water_drag': 0x104a0cc0,
        'gravity': 0x104a5df8, 'rest_squared': 0x104bb488,
        'destruction_height': 0x104c13c8, 'bounds_margin': 0x104aae40,
    }.items():
        rules[key] = struct.unpack('<d', image.read(address, 8))[0]
    for key, address in {'sea_height': 0x104ad010, 'blight_radius_scale': 0x104a0c54,
                         'water_trail_radius': 0x104a0c58, 'trail_squared': 0x104b1fe0,
                         'end_height': 0x104acff8}.items():
        rules[key] = struct.unpack('<f', image.read(address, 4))[0]

    upgrade_table = 'gui/powerupgradedata.csv'
    modifier_table = 'balance/balanceunlockmodifier.csv'
    modifiers = rows(files, modifier_table)
    upgrades = []
    for rank, row in enumerate((r for r in rows(files, upgrade_table) if r[0] == 'Card_GodPower_MeteorStrike'), 2):
        unlock = f'Upgrade_GodPower_MeteorStrike_{rank}'
        if row[4:6] != ['GEMS', 'UPGRADE'] or not any(r[:2] == [unlock, row[1]] for r in unlocks):
            raise CompileError(f'Unexpected Meteor Strike upgrade at rank {rank}')
        effects = {}
        for modifier in modifiers:
            if modifier[0] != unlock:
                continue
            operation, key, factor = modifier[1].split(',')
            if operation != 'Config' or not factor.startswith('m'):
                raise CompileError('Unexpected Meteor Strike upgrade modifier')
            effects[key] = float(factor[1:])
        keys = ('crater_radius', 'crater_depth', 'blight')
        if set(effects) != {tunables[key][0] for key in keys}:
            raise CompileError('Incomplete Meteor Strike upgrade modifiers')
        upgrades.append({'id': row[1], 'unlock': unlock, 'cost': int(row[3]), 'currency': 'gems',
                         'button': text(row[6], localization), 'title': text(row[7], localization),
                         'description': text(row[8], localization),
                         'multipliers': {key: effects[tunables[key][0]] for key in keys}})
    if len(upgrades) != 2:
        raise CompileError('Expected two original Meteor Strike upgrades')
    rules.update(card=card, power=power, population=int(level[0]), belief=int(cast[10]), upgrades=upgrades,
                 visuals=visual_rules(source, image, config),
                 native_instructions={name: address for name, (address, _) in native.items()})
    return rules, [upgrade_table, modifier_table]
