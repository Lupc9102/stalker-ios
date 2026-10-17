#include "exception_depth.h"
#include "wasm-rt-impl.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    wasm_rt_init();w2c_exception__depth module;
    assert(wasm_rt_impl_try()==WASM_RT_TRAP_NONE);
    wasm2c_exception__depth_instantiate(&module);
    for(unsigned i=0;i<10000;i++) {
        assert(w2c_exception__depth_run(&module)==17);
        assert(wasm_rt_call_stack_depth==0);
        assert(w2c_exception__depth_rethrow(&module)==17);
        assert(wasm_rt_call_stack_depth==0);
        assert(w2c_exception__depth_normal(&module)==42);
        assert(wasm_rt_call_stack_depth==0);
    }
    wasm2c_exception__depth_free(&module);wasm_rt_free();
    puts("Exception unwinding: 10,000 nested catches, unmatched tags and rethrows retained balanced call depth.");
    return 0;
}
