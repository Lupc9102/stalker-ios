#pragma once
#include "wasm-rt.h"
#include <simde/wasm/simd128.h>
#include <stdatomic.h>
#include <stdint.h>
#ifndef WASM_RT_SIMD_TYPE_DEFINED
#define WASM_RT_SIMD_TYPE_DEFINED
typedef simde_v128_t v128;
#endif

/* Portable and conservative: bytewise atomics retain Wasm's allowed tearing
   without introducing ordinary C data races. Tune ARM64 after correctness. */
static inline void zone_simd_read(wasm_rt_shared_memory_t *memory, uint64_t at, uint8_t *bytes, uint64_t size) {
    if (at > memory->size || size > memory->size - at) wasm_rt_trap(WASM_RT_TRAP_OOB);
    for (uint64_t i = 0; i < size; ++i) bytes[i] = atomic_load_explicit(memory->data + at + i, memory_order_relaxed);
}
static inline v128 v128_load_shared(uint8_t *base, uint64_t size, wasm_rt_shared_memory_t *memory, uint64_t at) {
    (void)base; (void)size;
    uint8_t bytes[16]; zone_simd_read(memory, at, bytes, 16);
    return simde_wasm_v128_load(bytes);
}
static inline void v128_store_shared(uint8_t *base, uint64_t size, wasm_rt_shared_memory_t *memory, uint64_t at, v128 value) {
    (void)base; (void)size;
    if (at > memory->size || 16 > memory->size - at) wasm_rt_trap(WASM_RT_TRAP_OOB);
    uint8_t bytes[16]; simde_wasm_v128_store(bytes, value);
    for (int i = 0; i < 16; ++i) atomic_store_explicit(memory->data + at + i, bytes[i], memory_order_relaxed);
}
#define ZONE_EXTENDING_LOAD(name, operation) \
static inline v128 name(uint8_t *base, uint64_t size, wasm_rt_shared_memory_t *memory, uint64_t at) { \
    (void)base; (void)size; uint8_t bytes[8]; zone_simd_read(memory, at, bytes, 8); return operation(bytes); \
}
ZONE_EXTENDING_LOAD(i32x4_load16x4_shared, simde_wasm_i32x4_load16x4)
ZONE_EXTENDING_LOAD(u32x4_load16x4_shared, simde_wasm_u32x4_load16x4)
ZONE_EXTENDING_LOAD(u64x2_load32x2_shared, simde_wasm_u64x2_load32x2)
#undef ZONE_EXTENDING_LOAD

#define ZONE_PART_LOAD(bits, bytes, suffix) \
static inline v128 zone_v128_load##bits##_##suffix##_shared(uint8_t *base, uint64_t size, wasm_rt_shared_memory_t *m, uint64_t at) { \
    (void)base; (void)size; uint8_t data[bytes]; zone_simd_read(m, at, data, bytes); return simde_wasm_v128_load##bits##_##suffix(data); \
}
ZONE_PART_LOAD(8, 1, splat)
ZONE_PART_LOAD(16, 2, splat)
ZONE_PART_LOAD(32, 4, splat)
ZONE_PART_LOAD(64, 8, splat)
ZONE_PART_LOAD(32, 4, zero)
ZONE_PART_LOAD(64, 8, zero)
#undef ZONE_PART_LOAD

#define ZONE_LANE(bits, bytes, lane) \
static inline v128 zone_v128_load##bits##_lane##lane##_shared(uint8_t *base, uint64_t size, wasm_rt_shared_memory_t *m, uint64_t at, v128 value) { \
    (void)base; (void)size; uint8_t data[bytes]; zone_simd_read(m, at, data, bytes); return simde_wasm_v128_load##bits##_lane(data, value, lane); \
} \
static inline void zone_v128_store##bits##_lane##lane##_shared(uint8_t *base, uint64_t size, wasm_rt_shared_memory_t *m, uint64_t at, v128 value) { \
    (void)base; (void)size; if (at > m->size || bytes > m->size - at) wasm_rt_trap(WASM_RT_TRAP_OOB); \
    uint8_t data[bytes]; simde_wasm_v128_store##bits##_lane(data, value, lane); \
    for (int i = 0; i < bytes; ++i) atomic_store_explicit(m->data + at + i, data[i], memory_order_relaxed); \
}
ZONE_LANE(8, 1, 0) ZONE_LANE(8, 1, 1) ZONE_LANE(8, 1, 2) ZONE_LANE(8, 1, 3)
ZONE_LANE(8, 1, 4) ZONE_LANE(8, 1, 5) ZONE_LANE(8, 1, 6) ZONE_LANE(8, 1, 7)
ZONE_LANE(8, 1, 8) ZONE_LANE(8, 1, 9) ZONE_LANE(8, 1, 10) ZONE_LANE(8, 1, 11)
ZONE_LANE(8, 1, 12) ZONE_LANE(8, 1, 13) ZONE_LANE(8, 1, 14) ZONE_LANE(8, 1, 15)
ZONE_LANE(16, 2, 0) ZONE_LANE(16, 2, 1) ZONE_LANE(16, 2, 2) ZONE_LANE(16, 2, 3)
ZONE_LANE(16, 2, 4) ZONE_LANE(16, 2, 5) ZONE_LANE(16, 2, 6) ZONE_LANE(16, 2, 7)
ZONE_LANE(32, 4, 0) ZONE_LANE(32, 4, 1) ZONE_LANE(32, 4, 2) ZONE_LANE(32, 4, 3)
ZONE_LANE(64, 8, 0) ZONE_LANE(64, 8, 1)
#undef ZONE_LANE
