#pragma once
#include "wasm-rt.h"
#include <stdint.h>
extern _Thread_local uintptr_t zone_native_stack_floor;
void zone_native_stack_init(void);
static inline void zone_check_native_stack(void) {
    if(!zone_native_stack_floor)zone_native_stack_init();
    char current;
    if((uintptr_t)&current<zone_native_stack_floor)wasm_rt_trap(WASM_RT_TRAP_EXHAUSTION);
}
