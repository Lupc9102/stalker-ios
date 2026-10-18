#include "Diagnostics.h"
#include <stdio.h>
#include <string.h>
#include <execinfo.h>

_Thread_local char zone_indirect_detail[256];
static void hash_string(wasm_rt_func_type_t type,char output[65]) {
    if(!type){snprintf(output,65,"none");return;}
    for(unsigned i=0;i<32;i++)snprintf(output+2*i,3,"%02x",(unsigned char)type[i]);
}
void zone_indirect_failure(const wasm_rt_funcref_table_t *table,wasm_rt_func_type_t expected,
                           uint64_t index,const char *caller) {
    const wasm_rt_funcref_t *f=index<table->size?&table->data[index]:NULL;
    const char *reason=!f?"out of bounds":!f->func?"missing function":
        !f->func_type?"missing type":!expected?"missing expected type":"type mismatch";
    snprintf(zone_indirect_detail,sizeof zone_indirect_detail,"%s: index=%llu table=%llu (%s)",
        caller,(unsigned long long)index,(unsigned long long)table->size,reason);
    char actual_hash[65],expected_hash[65];
    hash_string(expected,expected_hash);hash_string(f?f->func_type:NULL,actual_hash);
    fprintf(stderr,"[engine diagnostic] indirect call rejected: %s\n  expected=%s\n  actual=%s\n",
        zone_indirect_detail,expected_hash,actual_hash);fflush(stderr);
}
void zone_diagnostic_backtrace(const char *stage) {
    fprintf(stderr,"[engine diagnostic] Native backtrace at %s\n",stage);fflush(stderr);
    void *frames[48];int count=backtrace(frames,48);backtrace_symbols_fd(frames,count,2);
}
