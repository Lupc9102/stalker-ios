"""Boundary checks for private X-Ray asset extraction, without game assets."""
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

spec = importlib.util.spec_from_file_location('xray_archives', Path(__file__).resolve().parents[1] / 'Scripts/xray_archives.py')
archives = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archives)


class ArchiveTests(unittest.TestCase):
    def make_archive(self, directory, name='scripts/example.script', crc=None, position=8):
        data = b'fixture data, not executable code'
        encoded = name.encode('cp1251')
        record = struct.pack('<HIII', 16 + len(encoded), len(data), len(data),
                             zlib.crc32(data) if crc is None else crc) + encoded + struct.pack('<I', position)
        path = Path(directory) / 'test.db'
        path.write_bytes(struct.pack('<II', 0, len(data)) + data + struct.pack('<II', 1, len(record)) + record)
        return path, data

    def test_reads_crc_checked_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            path, data = self.make_archive(directory)
            archive = archives.Archive(path, None, None)
            self.assertEqual(archive.read('scripts/example.script'), data)

    def test_rejects_corrupt_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            path, _ = self.make_archive(directory, crc=1)
            archive = archives.Archive(path, None, None)
            with self.assertRaisesRegex(ValueError, 'CRC mismatch'):
                archive.read('scripts/example.script')

    def test_rejects_parent_escape(self):
        with tempfile.TemporaryDirectory() as directory:
            path, _ = self.make_archive(directory, name='scripts/../../escape.script')
            with self.assertRaisesRegex(ValueError, 'Unsafe archive member'):
                archives.Archive(path, None, None)

    def test_rejects_out_of_file_member(self):
        with tempfile.TemporaryDirectory() as directory:
            path, _ = self.make_archive(directory, position=0xFFFFFFF0)
            with self.assertRaisesRegex(ValueError, 'exceeds file size'):
                archives.Archive(path, None, None)

    def test_rejects_truncated_index(self):
        with tempfile.TemporaryDirectory() as directory:
            path, _ = self.make_archive(directory)
            path.write_bytes(path.read_bytes()[:-1])
            with self.assertRaisesRegex(ValueError, 'chunk exceeds file size'):
                archives.Archive(path, None, None)
