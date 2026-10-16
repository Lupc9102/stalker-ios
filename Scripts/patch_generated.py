"""Fix WABT 1.0.42's shared-memory bulk operations, with checked patch points.

Only valid for this pipeline's one imported shared memory. Do not generalize
to mixed-memory modules by casting incompatible runtime structures.
"""
import argparse
from pathlib import Path
import re


def patch(directory: Path, module='xray'):
    header = (directory / f'{module}.h').read_text()
    if len(re.findall(r'extern wasm_rt_shared_memory_t\*', header)) != 1 or 'wasm_rt_memory_t *' in header:
        raise ValueError('Expected exactly one imported shared memory and no unshared memories.')
    path = directory / f'{module}-impl.h'
    source = path.read_text()
    if 'ZONE_SHARED_BULK' in source:
        patch_simd_calls(directory, module)
        return
    replacements = {
        'memory_fill': '''/* ZONE_SHARED_BULK */
static inline void memory_fill(wasm_rt_shared_memory_t* mem, u64 d, u32 val, u64 n) {
  RANGE_CHECK(mem, d, n);
  for (u64 i = 0; i < n; ++i) atomic_store_explicit(mem->data + d + i, (uint8_t)val, memory_order_relaxed);
}''',
        'memory_copy': '''static inline void memory_copy(wasm_rt_shared_memory_t* dest,
                               const wasm_rt_shared_memory_t* src,
                               u64 dest_addr, u64 src_addr, u64 n) {
  RANGE_CHECK(dest, dest_addr, n);
  RANGE_CHECK(src, src_addr, n);
  if (dest == src && dest_addr > src_addr && dest_addr - src_addr < n) {
    while (n) { --n; atomic_store_explicit(dest->data + dest_addr + n,
        atomic_load_explicit(src->data + src_addr + n, memory_order_relaxed), memory_order_relaxed); }
  } else {
    for (u64 i = 0; i < n; ++i) atomic_store_explicit(dest->data + dest_addr + i,
        atomic_load_explicit(src->data + src_addr + i, memory_order_relaxed), memory_order_relaxed);
  }
}''',
        'memory_init': '''static inline void memory_init(wasm_rt_shared_memory_t* dest,
                               const u8* src, u32 src_size, u64 dest_addr, u32 src_addr, u32 n) {
  if ((uint64_t)src_addr + n > src_size) TRAP(OOB);
  RANGE_CHECK(dest, dest_addr, n);
  for (u64 i = 0; i < n; ++i) atomic_store_explicit(dest->data + dest_addr + i, src[src_addr + i], memory_order_relaxed);
}'''
    }
    for name, replacement in replacements.items():
        pattern = rf'static inline void {name}\(.*?\n\}}'
        source, count = re.subn(pattern, lambda _: replacement, source, flags=re.S)
        if count != 1:
            raise ValueError(f'Expected one {name} definition, found {count}.')
    path.write_text(source)
    patch_simd_calls(directory, module)


def patch_simd_calls(directory, module):
    # WABT emits the unshared-memory helper for SIMD lane/splat/zero accesses.
    # Rewrite call sites to checked atomic-byte helpers, retaining the original
    # unused unshared helpers in the generated support header.
    for path in directory.glob(f'{module}_*.c'):
        source = path.read_text()
        source = re.sub(r'\b(v128_(?:load|store)(?:8|16|32|64)_(?:zero|splat|lane[0-9]+))\(',
                        r'zone_\1_shared(', source)
        path.write_text(source)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('--module', default='xray')
    options = parser.parse_args()
    patch(options.directory, options.module)
