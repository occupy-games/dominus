"""Recover the original Belief tutorial's house grouping and fill bindings."""
import hashlib
import struct

from tools.current_cards import ROOT
from tools.native_scenery_oracle import NativeImage


def extract(source=ROOT/'data/godus2_4'):
    raw = (source/'godus.s86').read_bytes()
    image = NativeImage(raw)
    bindings = {'ProcessBiggestClumpOfAbodesOfType': (0x1060d7d0, 0x102472a0),
                'AbodeFillBelief': (0x1060d520, 0x1023cf00),
                'IsDebug': (0x1060d3a0, 0x1023c2e0)}
    for name, (address, function) in bindings.items():
        label, target = struct.unpack('<II', image.read(address, 8))
        if image.read(label, len(name) + 1) != name.encode() + b'\0' or target != function:
            raise ValueError('Unexpected original belief tutorial binding')
    if image.read(0x10246e1a, 7) != bytes.fromhex('83be3401000001'):
        raise ValueError('Unexpected original completed-house filter')
    if image.read(0x100b8a47, 3) != bytes.fromhex('d94074'):
        raise ValueError('Unexpected original maximum-belief field')
    debug_flag = 0x110a4f70
    if image.read(0x1023c2e8, 6) != b'\x39\x05' + struct.pack('<I', debug_flag):
        raise ValueError('Unexpected original debug-mode lookup')
    if not any(base+size <= debug_flag and debug_flag+4 <= base+virtual
               for base, _, size, virtual in image.sections):
        raise ValueError('Original debug-mode flag must start in zero-initialized data')
    return dict(version=1, executable_sha256=hashlib.sha256(raw).hexdigest(),
                complete_state=1, include_unfinished_default=True, debug_default=False,
                bindings={name: hex(function) for name, (_, function) in bindings.items()},
                native_routines={hex(start): image.read(start, end-start).hex() for start, end in [
                    (0x10246d80, 0x10247358), (0x1023cf00, 0x1023cf3d),
                    (0x100b8a30, 0x100b8a71), (0x1023c2e0, 0x1023c301)]})
