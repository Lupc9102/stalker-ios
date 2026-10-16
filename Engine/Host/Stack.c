#define _GNU_SOURCE 1
#include "Stack.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

_Thread_local uintptr_t zone_native_stack_floor;
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
