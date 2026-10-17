#define _GNU_SOURCE 1
#include "Stack.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <execinfo.h>

_Thread_local uintptr_t zone_native_stack_floor;
_Noreturn void zone_native_stack_exhausted(void) {
    char current;
    fprintf(stderr,"[engine] Native stack guard: guest depth=%u, bytes above reserve=%lld\n",
            wasm_rt_call_stack_depth,(long long)((uintptr_t)&current-zone_native_stack_floor));
    void *frames[64];int count=backtrace(frames,64);backtrace_symbols_fd(frames,count,2);
    wasm_rt_trap(WASM_RT_TRAP_EXHAUSTION);
}
void zone_native_stack_init(void) {
    uintptr_t bottom=0;size_t size=0;
#if defined(__APPLE__)
    size=pthread_get_stacksize_np(pthread_self());
    bottom=(uintptr_t)pthread_get_stackaddr_np(pthread_self())-size;
#else
    pthread_attr_t attributes;void *address=NULL;
    if(pthread_getattr_np(pthread_self(),&attributes))abort();
    int result=pthread_attr_getstack(&attributes,&address,&size);pthread_attr_destroy(&attributes);
    if(result)abort();bottom=(uintptr_t)address;
#endif
    // Generated code grows downwards on the supported ARM64/x86_64 targets.
    // Leave room for a native trap and its error reporting before the OS guard.
    const size_t reserve=128*1024;
    if(!bottom||size<=reserve) { fprintf(stderr,"[engine] Native thread stack too small\n");abort(); }
    zone_native_stack_floor=bottom+reserve;
}
