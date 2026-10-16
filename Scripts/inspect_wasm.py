"""Inventory the engine's actual Wasm import boundary without executing JS."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re


class Reader:
    def __init__(self, data): self.data, self.offset = data, 0
    def take(self, size):
        if size < 0 or self.offset + size > len(self.data): raise ValueError('Truncated Wasm')
        result = self.data[self.offset:self.offset + size]; self.offset += size; return result
    def byte(self): return self.take(1)[0]
    def integer(self):
        result = shift = 0
        for _ in range(10):
            value = self.byte(); result |= (value & 127) << shift
            if not value & 128: return result
            shift += 7
        raise ValueError('Invalid LEB128 integer')
    def string(self): return self.take(self.integer()).decode('utf-8')


def limits(reader):
    flags = reader.integer()
    result = {'shared': bool(flags & 2), 'memory64': bool(flags & 4), 'initial_pages': reader.integer()}
    result['maximum_pages'] = reader.integer() if flags & 1 else None
    return result


def category(name):
    if re.search(r'_gl|webgl', name, re.I): return 'graphics'
    if re.search(r'_al[cA-Z]', name): return 'audio'
    if re.search(r'wasmfs|fd_|path_', name): return 'filesystem'
    if re.search(r'thread|futex|mailbox', name): return 'threads'
    return 'runtime'


def inspect(wasm: Path, javascript: Path | None = None):
    raw = wasm.read_bytes(); reader = Reader(raw)
    if reader.take(8) != b'\0asm\x01\0\0\0': raise ValueError('Not a WebAssembly v1 module')
    names = {}
    if javascript:
        text = javascript.read_text()
        marker = 'wasmImports={'
        if marker not in text: raise ValueError('Expected Emscripten wasmImports object')
        start = text.index(marker) + len(marker)
        body = text[start:text.index('}', start)]
        names = dict(re.findall(r'([A-Za-z_$][\w$]*):([A-Za-z_$][\w$]*)', body))
    imports, exports = [], []
    while reader.offset < len(raw):
        section_id = reader.byte(); section = Reader(reader.take(reader.integer()))
        if section_id == 2:
            for _ in range(section.integer()):
                module, field, kind = section.string(), section.string(), section.byte()
                item = {'module': module, 'field': field, 'kind': kind, 'name': names.get(field, field)}
                item['category'] = category(item['name'])
                if kind == 0: item['type_index'] = section.integer()
                elif kind == 1: item['reference_type'] = section.byte(); item.update(limits(section))
                elif kind == 2: item.update(limits(section))
                elif kind == 3: item['value_type'] = section.byte(); item['mutable'] = bool(section.byte())
                elif kind == 4: item['attribute'] = section.byte(); item['type_index'] = section.integer()
                else: raise ValueError(f'Unknown import kind {kind}')
                imports.append(item)
        elif section_id == 7:
            for _ in range(section.integer()):
                exports.append({'field': section.string(), 'kind': section.byte(), 'index': section.integer()})
    return {'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw), 'imports': imports,
            'exports': exports, 'categories': dict(Counter(x['category'] for x in imports if x['kind'] == 0))}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('wasm', type=Path); parser.add_argument('--javascript', type=Path); parser.add_argument('--out', type=Path)
    args = parser.parse_args(); report = inspect(args.wasm, args.javascript)
    if args.out: args.out.parent.mkdir(parents=True, exist_ok=True); args.out.write_text(json.dumps(report, indent=2) + '\n')
    else: print(json.dumps(report, indent=2))
