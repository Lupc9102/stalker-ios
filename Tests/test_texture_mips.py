"""Existing mip payloads must survive selection byte for byte."""
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Scripts'))
from prepare_texture_overlay import select_mips


def fixture(format=b'DXT1', cube=False):
    block = 8 if format == b'DXT1' else 16
    levels = [bytes([number + 1]) * size for number, size in enumerate([4 * block, block, block, block])]
    header = bytearray(128)
    header[:4] = b'DDS '
    struct.pack_into('<7I', header, 4, 124, 0xA1007, 8, 8, len(levels[0]), 0, 4)
    struct.pack_into('<II4s5I', header, 76, 32, 4, format, 0, 0, 0, 0, 0)
    struct.pack_into('<II', header, 108, 0x401008, 0xFE00 if cube else 0)
    return bytes(header) + b''.join(levels), levels


class TextureMipTests(unittest.TestCase):
    def test_preserves_remaining_compressed_levels(self):
        source, levels = fixture()
        selected, record = select_mips(source, 4)
        self.assertEqual(selected[128:], b''.join(levels[1:]))
        self.assertEqual(struct.unpack_from('<II', selected, 12), (4, 4))
        self.assertEqual(struct.unpack_from('<I', selected, 20)[0], 8)
        self.assertEqual(struct.unpack_from('<I', selected, 28)[0], 3)
        self.assertEqual(record['source_rgba_bytes'], 340)
        self.assertEqual(record['rgba_bytes'], 84)

    def test_selects_bc3_blocks_without_reencoding(self):
        source, levels = fixture(b'DXT5')
        selected, record = select_mips(source, 2)
        self.assertEqual(selected[128:], b''.join(levels[2:]))
        self.assertEqual(record['dropped_mips'], 2)

    def test_single_remaining_mip_clears_chain_flags(self):
        source, levels = fixture()
        selected, _ = select_mips(source, 1)
        self.assertEqual(selected[128:], levels[-1])
        self.assertFalse(struct.unpack_from('<I', selected, 8)[0] & 0x20000)
        self.assertFalse(struct.unpack_from('<I', selected, 108)[0] & 0x400008)

    def test_leaves_small_and_cube_textures_untouched(self):
        source, _ = fixture()
        self.assertIsNone(select_mips(source, 8))
        source, _ = fixture(cube=True)
        self.assertIsNone(select_mips(source, 4))

    def test_rejects_truncated_chain(self):
        source, _ = fixture()
        with self.assertRaisesRegex(ValueError, 'Truncated DDS'):
            select_mips(source[:-1], 4)
