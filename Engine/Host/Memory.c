#define _DARWIN_C_SOURCE 1
#define _DEFAULT_SOURCE 1
#include "Host.h"
#include <sys/mman.h>
#include <stdio.h>
#include <string.h>

// A fixed-capacity, non-executable mapping keeps borrowed native pointers
// stable across worker, audio and GPU calls. Pages become resident on demand.
bool z_memory_open(ZRuntime *runtime,u32 megabytes) {
    if(megabytes<2048||megabytes>16384||runtime->memory.data)return false;
    u64 bytes=(u64)megabytes*1024*1024;
    void *base=mmap(NULL,(size_t)bytes,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
    if(base==MAP_FAILED){perror("Reserve native engine heap");return false;}
    wasm_rt_shared_memory_t *m=&runtime->memory;memset(m,0,sizeof *m);
    m->data=base;m->data_end=m->data+bytes;m->size=bytes;
    m->pages=m->max_pages=bytes/WASM_DEFAULT_PAGE_SIZE;m->is64=true;m->page_size=WASM_DEFAULT_PAGE_SIZE;
    if(pthread_mutex_init(&m->mem_lock,NULL)){munmap(base,bytes);memset(m,0,sizeof *m);return false;}
    fprintf(stderr,"[engine] Fixed native heap: %u MiB address space; no executable mapping\n",megabytes);
    return true;
}
void z_memory_close(ZRuntime *runtime) {
    wasm_rt_shared_memory_t *m=&runtime->memory;if(!m->data)return;
    munmap((void *)m->data,(size_t)m->size);pthread_mutex_destroy(&m->mem_lock);memset(m,0,sizeof *m);
}
