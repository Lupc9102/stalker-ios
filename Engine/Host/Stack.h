#pragma once
#include "wasm-rt.h"
#include "Atomics.h"
#include <stdint.h>
extern _Thread_local uintptr_t zone_native_stack_floor;
void zone_native_stack_init(void);
_Noreturn void zone_native_stack_exhausted(void);
static inline void zone_check_native_stack(void) {
    if(!zone_native_stack_floor)zone_native_stack_init();
    char current;
    if((uintptr_t)&current<zone_native_stack_floor)zone_native_stack_exhausted();
#if WASM_RT_STACK_DEPTH_COUNT
    if(wasm_rt_call_stack_depth>=WASM_RT_MAX_CALL_STACK_DEPTH)zone_native_stack_exhausted();
#endif
    if(zone_native_checkpoint_handler&&!(++zone_native_checkpoint_counter&1023))zone_native_checkpoint();
}
