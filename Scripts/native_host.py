"""Generate typed import bindings for the pinned engine's native host.

Unsupported imports trap by name. No graphics or gameplay success is simulated.
"""
import argparse
import json
from pathlib import Path
import re
from patch_engine_snapshot import SOURCE_SHA256, OUTPUT_SHA256


def generate(directory, javascript, host, gles=False):
    report = json.loads((directory / 'imports.json').read_text())
    header = (directory / 'xray.h').read_text()
    names = {(i['module'], i['field']): i['name'] for i in report['imports']}
    matches = re.findall(r"/\* import: '([^']+)' '([^']+)' \*/\n(\w+) (w2c_\w+)\(([^;]+)\);", header)
    functions = {names[(m, f)]: (ret, fn, args.split(',')[1:]) for m, f, ret, fn, args in matches}
    if len(functions) != 489 or report['sha256'] not in {SOURCE_SHA256, OUTPUT_SHA256}:
        raise ValueError('Native host requires the reviewed engine snapshot')
    implementations = set()
    for path in host.glob('*.c'):
        if path.stem in ('Graphics', 'GraphicsEGL') and not gles:
            continue
        implementations.update(re.findall(r'\b(?:void|u32|u64|f32|f64)\s+Z_IMPORT(\w+)\s*\(', path.read_text()))
    if gles:
        from gles_bindings import generate as generate_gles
        implementations.update(generate_gles(directory, functions, host.parent / 'ABI/GLES3.h'))
    event_codes = {'keypress': 1, 'keydown': 2, 'keyup': 3, 'mousedown': 5,
                   'mouseup': 6, 'mousemove': 8, 'wheel': 9, 'resize': 10,
                   'blur': 12, 'focus': 13, 'fullscreenchange': 19,
                   'pointerlockchange': 20, 'visibilitychange': 21,
                   'touchstart': 22, 'touchend': 23, 'touchmove': 24,
                   'touchcancel': 25, 'gamepadconnected': 26,
                   'gamepaddisconnected': 27, 'beforeunload': 28,
                   'mouseenter': 33, 'mouseleave': 34}
    registrations = {}
    for name in functions:
        event = re.fullmatch(r'_emscripten_set_(\w+)_callback_on_thread', name)
        if event and event[1] in event_codes:
            registrations[name] = event_codes[event[1]]
            implementations.add(name)
    aliases = ['/* Generated typed ABI aliases. */\n#pragma once\n#include "xray.h"\n']
    for name, (_, fn, _) in functions.items(): aliases.append(f'#define Z_IMPORT{name} {fn}\n')
    segment = re.search(r'elem_segment_exprs_\w+\[\] = \{(.*?)\n\};\n\nstatic void init_tables', (directory / 'xray_0.c').read_text(), re.S)
    if not segment: raise ValueError('Missing reviewed function-table segment')
    by_symbol = {fn: name for name, (_, fn, _) in functions.items()}
    for index, entry in enumerate(line for line in segment[1].splitlines() if line.lstrip().startswith('{')):
        imported = re.search(r'wrap_(w2c_a_\w+)', entry)
        if imported: aliases.append(f'#define Z_TABLE{by_symbol[imported[1]]} {index+1}\n')
    js = javascript.read_text()
    for name, field in re.findall(r'(\w+)=(?:Module\["[^\"]+"\]=)?wasmExports\["([^\"]+)"\]', js):
        export = re.search(r"/\* export: '" + re.escape(field) + r"' \*/\n\w+ (w2c_\w+)\(", header)
        if export: aliases.append(f'#define Z_EXPORT{name} {export[1]}\n')
    table = next(i for i in report['exports'] if i['kind'] == 1)
    table_export = re.search(r"/\* export: '" + re.escape(table['field']) + r"' \*/\n[^\n]*?\b(w2c_\w+)\(", header)
    if not table_export: raise ValueError('Missing indirect function table export')
    aliases.append(f'#define Z_EXPORT__indirect_function_table {table_export[1]}\n')
    (directory / 'NativeABI.h').write_text(''.join(aliases))
    output = ['#include "Host.h"\n#include <string.h>\n']
    for name, (ret, fn, types) in functions.items():
        types = [t.strip() for t in types]
        declaration = ', '.join(['struct w2c_a *h'] + [f'{t} p{i}' for i, t in enumerate(types)])
        if name in registrations:
            unused = ''.join(f'(void)p{i};' for i in range(len(types)))
            if len(types) == 5: user, callback, thread, surface, capture = 'p1', 'p3', 'p4', 'p0', 'p2'
            elif len(types) == 4: user, callback, thread, surface, capture = 'p0', 'p2', 'p3', '1', 'p1'
            elif len(types) == 3: user, callback, thread, surface, capture = 'p0', 'p1', 'p2', '2', '0'
            else: raise ValueError('Unexpected native event registration signature')
            output.append(f'{ret} {fn}({declaration}) {{ {unused} return z_register_event(h,{registrations[name]},{user},{callback},{thread},{surface},{capture}!=0); }}\n')
        elif name not in implementations:
            unused = ''.join(f'(void)p{i};' for i in range(len(types)))
            output.append(f'{ret} {fn}({declaration}) {{ {unused} z_missing(h, {json.dumps(name)}); }}\n')
        # WABT packs the guest arguments in a naturally aligned C structure.
        fields = ''.join(f'{t} p{i};' for i, t in enumerate(types))
        unpack = f'struct {{{fields}}} a; memcpy(&a,stack,sizeof a);' if types else '(void)stack;'
        call = f'{fn}((struct w2c_a *)*instance' + ''.join(f',a.p{i}' for i in range(len(types))) + ')'
        result = call + ';' if ret == 'void' else f'{ret} result={call}; memcpy(stack,&result,sizeof result);'
        output.append(f'void wasm_tailcall_{fn}(void **instance,void *stack,wasm_rt_tailcallee_t *next) {{ {unpack} {result} next->fn=NULL; }}\n')
    # Emscripten's proxy packet stores an i64 tag/value or f64 tag/value per argument.
    proxy = re.search(r'var proxiedFunctionTable=\[([^\]]+)\]', js)
    if not proxy: raise ValueError('Missing proxy function table')
    output.append('double z_proxy(struct w2c_a *h,u32 index,u64 packet,u32 bytes) {\n switch(index) {\n')
    remap = {'exitOnMainThread': '_exit', 'pthreadCreateProxied': '___pthread_create_js'}
    for index, name in enumerate(proxy[1].split(',')):
        name = remap.get(name, name)
        if name not in functions: continue
        ret, fn, types = functions[name]
        args = [f'({t.strip()})z_proxy_argument(h,packet,{i},bytes)' for i, t in enumerate(types)]
        call = f'{fn}(h' + ''.join(',' + a for a in args) + ')'
        body = f'{call};return 0;' if ret == 'void' else f'return (double){call};'
        output.append(f'case {index}: {body}\n')
    output.append('default: z_missing(h,"unmapped Emscripten proxy index");\n }\n}\n')
    (directory / 'native_imports.c').write_text(''.join(output))
    (directory / 'native-coverage.json').write_text(json.dumps({
        'engine_sha256': report['sha256'],
        'implemented': sorted(implementations),
        'unsupported': sorted(set(functions) - implementations),
        'gles': gles,
    }, indent=2) + '\n')
    print(f'Native host: {len(implementations)} typed implementations; {len(functions)-len(implementations)} explicit unsupported traps')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('javascript', type=Path)
    parser.add_argument('--host', type=Path, default=Path(__file__).resolve().parents[1] / 'Engine/Host')
    parser.add_argument('--gles', action='store_true', help='Generate the real native GLES 3 backend')
    args = parser.parse_args()
    generate(args.directory, args.javascript, args.host, args.gles)
