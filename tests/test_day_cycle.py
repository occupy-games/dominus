import hashlib
from pathlib import Path
import unittest

from tools.current_cards import decode_archive, rows
from tools.day_cycle import extract

ROOT = Path(__file__).resolve().parents[1]


class DayCycleTests(unittest.TestCase):
    def test_original_native_day_functions_and_current_lengths(self):
        raw = (ROOT/'data/godus2_4/godus.s86').read_bytes()
        files = decode_archive((ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes())
        config = {r[0]:r[1] for r in rows(files,'config.csv') if len(r)>1}
        data = extract(raw,config)
        self.assertEqual(data['executable_sha256'],hashlib.sha256(raw).hexdigest())
        self.assertEqual(data['functions']['Midday']['terms'],[['DayTimeLength',.5],['DawnToDayLength',1]])
        self.assertEqual(data['functions']['Sunset']['terms'],[['DayTimeLength',1],['DawnToDayLength',1],['DayToDuskLength',1]])
        self.assertEqual(data['functions']['Sunrise']['terms'],[['DawnToDayLength',1]])
        self.assertEqual(data['functions']['Sunrise']['value'],30)
        self.assertEqual(data['functions']['Sunrise']['routine'],'0x1019cc50')
        self.assertEqual(data['functions']['Midday']['value'],480)
        self.assertEqual(data['functions']['Sunset']['value'],960)
        self.assertEqual(data['functions']['Midnight']['value'],1080)
        self.assertEqual(data['period'],1200)
        self.assertEqual(data['configuration']['TimeOfDaySpeed'],1)
        self.assertEqual(data['functions']['Midday']['routine'],'0x1019cc80')
        self.assertEqual(data['functions']['Sunset']['routine'],'0x1019cc60')
        # Config values change the recovered expressions, not an invented clock.
        config['DayTimeLength']='100'
        changed=extract(raw,config)
        self.assertEqual(changed['functions']['Midday']['value'],80)
        self.assertEqual(changed['functions']['Sunset']['value'],160)
        self.assertEqual(changed['period'],400)

    def test_unknown_native_arithmetic_is_rejected(self):
        raw = bytearray((ROOT/'data/godus2_4/godus.s86').read_bytes())
        data=extract(raw,{})
        routine=bytes.fromhex(data['functions']['Midday']['bytes'])
        position=raw.index(routine)
        raw[position+4]=0
        with self.assertRaises(ValueError): extract(raw,{})
