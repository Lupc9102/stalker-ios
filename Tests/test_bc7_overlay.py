import importlib.util
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Scripts'))
available = importlib.util.find_spec('PIL') is not None
if available:
    from convert_bc7_overlay import convert


def block(red):
    # A valid BC7 mode-6 block: equal endpoints, zero indices, alpha 254.
    value, offset = 1 << 6, 7
    for endpoint in [red, red, 0, 0, 0, 0, 127, 127]:
        value |= endpoint << offset
        offset += 7
    return value.to_bytes(16, 'little')


def dds(cube=False):
    header = bytearray(148); header[:4] = b'DDS '
    struct.pack_into('<7I', header, 4, 124, 0x21007, 4, 4, 16, 0, 3)
    struct.pack_into('<3I', header, 76, 32, 4, int.from_bytes(b'DX10', 'little'))
    struct.pack_into('<II', header, 108, 0x401008, 0xFE00 if cube else 0)
    struct.pack_into('<5I', header, 128, 98, 3, 4 if cube else 0, 1, 0)
    return bytes(header) + b''.join(block(face * 10 + mip * 5) for face in range(6 if cube else 1) for mip in range(3))


@unittest.skipUnless(available, 'Optional offline BC7 converter requires Pillow')
class BC7Overlay(unittest.TestCase):
    def test_decodes_selected_mips_without_resizing(self):
        data, record = convert(dds(), 2)
        self.assertEqual(struct.unpack_from('<II', data, 12), (2, 2))
        self.assertEqual(data[128:132], bytes([10, 0, 0, 254]))
        self.assertEqual(data[144:148], bytes([20, 0, 0, 254]))
        self.assertEqual(len(data), 148)
        self.assertEqual(record['mips'], 2)

    def test_preserves_all_cube_faces_in_order(self):
        data, record = convert(dds(True), 2)
        self.assertEqual(record['faces'], 6)
        self.assertEqual(struct.unpack_from('<I', data, 112)[0], 0xFE00)
        self.assertEqual(len(data), 128 + 6 * 20)
        for face in range(6):
            self.assertEqual(data[128 + face * 20:132 + face * 20], bytes([face * 20 + 10, 0, 0, 254]))

    def test_rejects_incomplete_cube_and_leaves_srgb_alone(self):
        with self.assertRaises(ValueError):
            convert(dds(True)[:-1], 2)
        data = bytearray(dds()); struct.pack_into('<I', data, 128, 99)
        self.assertIsNone(convert(data, 2))
