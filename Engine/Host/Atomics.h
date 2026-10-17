#pragma once
#include "wasm-rt.h"
#include <stdint.h>

typedef void (*ZoneCheckpoint)(void *);
extern _Thread_local ZoneCheckpoint zone_native_checkpoint_handler;
extern _Thread_local void *zone_native_checkpoint_context;
extern _Thread_local uint32_t zone_native_checkpoint_counter;
void zone_native_checkpoint(void);

uint32_t zone_atomic_wait32(wasm_rt_shared_memory_t *, uint64_t, uint32_t, uint64_t);
uint32_t zone_atomic_wait64(wasm_rt_shared_memory_t *, uint64_t, uint64_t, uint64_t);
uint32_t zone_atomic_notify(wasm_rt_shared_memory_t *, uint64_t, uint32_t);
