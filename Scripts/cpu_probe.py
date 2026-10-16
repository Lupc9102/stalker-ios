"""Generate a diagnostic host which stops at the first unimplemented import.

This is deliberately NOT a gameplay runtime and is never used in the iOS app.
It distinguishes native module instantiation from running a game successfully.
"""
import argparse
import json
from pathlib import Path
import re


def generate(directory, inventory):
    header = (directory / 'xray.h').read_text()
    report = json.loads(inventory.read_text())
    memories = [item for item in report['imports'] if item['kind'] == 2]
    if len(memories) != 1 or not memories[0]['shared'] or not memories[0]['memory64']:
        raise ValueError('Probe expects the pinned engine’s single shared memory64 import.')
    memory = memories[0]
    names = {(item['module'], item['field']): item['name'] for item in report['imports']}
    functions = re.findall(r"/\* import: '([^']+)' '([^']+)' \*/\n(\w+) (w2c_\w+)\(([^;]+)\);", header)
    if len(functions) != sum(item['kind'] == 0 for item in report['imports']):
        raise ValueError('Generated header and inventory disagree about function imports.')
    if any(item[0] != 'a' for item in functions): raise ValueError('Unexpected import module')
    output = ['''/* Diagnostic only: generated trap imports, never a game runtime. */
#include "xray.h"
#include <stdio.h>
#include <stdlib.h>
struct w2c_a { wasm_rt_shared_memory_t memory; };
wasm_rt_shared_memory_t* w2c_a_a(struct w2c_a *host) { return &host->memory; }
static _Noreturn void missing(const char *name) {
    fprintf(stderr, "Native CPU probe stopped at unimplemented browser import: %s\\n", name);
    exit(78);
}
''']
    for module, field, return_type, function, arguments in functions:
        semantic = json.dumps(names[(module, field)])
        types = [arg.strip() for arg in arguments.split(',')]
        declaration = ', '.join(f'{kind} p{i}' for i, kind in enumerate(types))
        unused = ''.join(f'(void)p{i};' for i in range(len(types)))
        output.append(f'{return_type} {function}({declaration}) {{ {unused} missing({semantic}); }}\n')
        output.append(f'void wasm_tailcall_{function}(void **a, void *b, wasm_rt_tailcallee_t *c) '
                      f'{{ (void)a;(void)b;(void)c;missing({semantic}); }}\n')
    output.append(f'''int main(void) {{
    wasm_rt_init();
    struct w2c_a host = {{0}};
    w2c_xray *engine = calloc(1, sizeof(*engine));
    if (!engine) return 1;
    wasm_rt_allocate_memory_shared(&host.memory, {memory['initial_pages']}, {memory['maximum_pages']}, true, WASM_DEFAULT_PAGE_SIZE);
    puts("Instantiating statically compiled STALKER module; no JIT, no game files.");
    fflush(stdout);
    wasm2c_xray_instantiate(engine, &host);
    puts("Native module instantiation succeeded. Engine main was NOT called; gameplay is untested.");
    wasm2c_xray_free(engine);
    wasm_rt_free_memory_shared(&host.memory);
    free(engine); wasm_rt_free();
    return 0;
}}
''')
    (directory / 'cpu_probe.c').write_text(''.join(output))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('directory', type=Path); parser.add_argument('inventory', type=Path)
    args = parser.parse_args(); generate(args.directory, args.inventory)
