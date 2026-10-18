#pragma once
#include "wasm-rt.h"
#include <stdint.h>
extern _Thread_local char zone_indirect_detail[256];
void zone_indirect_failure(const wasm_rt_funcref_table_t *, wasm_rt_func_type_t,
                           uint64_t index, const char *caller);
void zone_diagnostic_backtrace(const char *stage);
