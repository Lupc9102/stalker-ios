#include "indirect_diagnostics.h"
#include "Diagnostics.h"
#include "wasm-rt-impl.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    wasm_rt_init();w2c_indirect__diagnostics module;
    assert(wasm_rt_impl_try()==WASM_RT_TRAP_NONE);
    wasm2c_indirect__diagnostics_instantiate(&module);
    wasm_rt_trap_t trap=wasm_rt_impl_try();
    if(!trap){w2c_indirect__diagnostics_badtype(&module);assert(!"Wrong type did not trap");}
    assert(trap==WASM_RT_TRAP_CALL_INDIRECT);
    assert(strstr(zone_indirect_detail,"index=0")&&strstr(zone_indirect_detail,"type mismatch"));
    trap=wasm_rt_impl_try();
    if(!trap){w2c_indirect__diagnostics_badindex(&module);assert(!"Bad index did not trap");}
    assert(trap==WASM_RT_TRAP_CALL_INDIRECT);
    assert(strstr(zone_indirect_detail,"index=9")&&strstr(zone_indirect_detail,"out of bounds"));
    wasm2c_indirect__diagnostics_free(&module);wasm_rt_free();
    puts("Real generated indirect calls: wrong type and bad index still trap, with call-site diagnostics.");
}
