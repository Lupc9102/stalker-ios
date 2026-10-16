import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('wasm_inspector', ROOT / 'Scripts/inspect_wasm.py')
inspector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inspector)


class WasmInventoryTests(unittest.TestCase):
    def test_shared_memory64_and_semantic_name(self):
        # One shared i64-addressed memory, then one timing function import.
        body = b'\x02\x01a\x01a\x02\x07\x01\x02\x01a\x01b\x00\x00'
        with tempfile.TemporaryDirectory() as directory:
            wasm = Path(directory) / 'test.wasm'; javascript = Path(directory) / 'test.js'
            wasm.write_bytes(b'\0asm\x01\0\0\0\x02' + bytes([len(body)]) + body)
            javascript.write_text('wasmImports={a:wasmMemory,b:_emscripten_get_now}')
            result = inspector.inspect(wasm, javascript)
            self.assertTrue(result['imports'][0]['shared'])
            self.assertTrue(result['imports'][0]['memory64'])
            self.assertEqual(result['imports'][0]['maximum_pages'], 2)
            self.assertEqual(result['imports'][1]['name'], '_emscripten_get_now')

    def test_truncated_binary_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            wasm = Path(directory) / 'test.wasm'; wasm.write_bytes(b'\0asm\x01\0\0\0\x02\x10\x00')
            with self.assertRaises(ValueError): inspector.inspect(wasm)

    def test_oversized_leb_rejected(self):
        with self.assertRaises(ValueError): inspector.Reader(b'\x80' * 11).integer()

    def test_invalid_magic_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            wasm = Path(directory) / 'test.wasm'; wasm.write_bytes(b'not-wasm')
            with self.assertRaises(ValueError): inspector.inspect(wasm)


if __name__ == '__main__': unittest.main()
