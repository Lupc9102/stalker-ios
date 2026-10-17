#define _POSIX_C_SOURCE 200809L
#include "Host.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

void z_call_void(struct w2c_a *h,u64 function,u64 argument) {
    wasm_rt_funcref_table_t *table=Z_EXPORT__indirect_function_table(&h->engine);
    if(function>=table->size)wasm_rt_trap(WASM_RT_TRAP_CALL_INDIRECT);
    wasm_rt_funcref_t f=table->data[function];
    wasm_rt_func_type_t expected=wasm2c_xray_get_func_type(1,0,WASM_RT_I64);
    if(!f.func||!f.func_type||memcmp(f.func_type,expected,32))wasm_rt_trap(WASM_RT_TRAP_CALL_INDIRECT);
    ((void (*)(void *,u64))f.func)(f.module_instance,argument);
}
void z_pump(struct w2c_a *h) {
    Z_EXPORT__emscripten_check_mailbox(&h->engine);
    if(h->heartbeat)Z_EXPORT_emscripten_proxy_execute_queue(&h->engine,h->heartbeat);
}
void Z_IMPORT__emscripten_init_main_thread_js(struct w2c_a *h,u64 thread) {
    h->pthread=thread;
    h->runtime->main_guest_thread=thread;
    Z_EXPORT__emscripten_thread_init(&h->engine,thread,1,1,1,4194304,0);
    Z_EXPORT__emscripten_tls_init(&h->engine);
}
void Z_IMPORT__emscripten_thread_set_strongref(struct w2c_a *h,u64 thread) { (void)h;(void)thread; }
void Z_IMPORT__emscripten_thread_cleanup(struct w2c_a *h,u64 thread) { (void)h;(void)thread; }
void Z_IMPORT__emscripten_thread_mailbox_await(struct w2c_a *h,u64 thread) { (void)h;(void)thread; }
void Z_IMPORT__emscripten_notify_mailbox_postmessage(struct w2c_a *h,u64 target,u64 source) {
    // Guest mailbox state is atomic. Parked native workers check it at most 5ms
    // later; no browser worker or JavaScript message loop is involved.
    (void)h;(void)target;(void)source;
}
void Z_IMPORT__wasmfs_thread_utils_heartbeat(struct w2c_a *h,u64 queue) { h->heartbeat=queue; }
typedef struct { struct w2c_a host;u64 routine,argument; } Worker;
static void *run_worker(void *pointer) {
    Worker *w=pointer;struct w2c_a *h=&w->host;z_current_thread=h;wasm_rt_init_thread();
    if(setjmp(h->yielded)==0) {
        wasm_rt_trap_t trap=wasm_rt_impl_try();
        if(trap){fprintf(stderr,"[engine] Worker %llu trapped: %s\n",(unsigned long long)h->pthread,wasm_rt_strerror(trap));atomic_fetch_add(&h->runtime->failures,1);return NULL;}
        wasm2c_xray_instantiate(&h->engine,h);
        u64 high=z_read64(h,h->pthread+80),size=z_read64(h,h->pthread+88);
        if(size>high)wasm_rt_trap(WASM_RT_TRAP_OOB);
        Z_EXPORT_emscripten_stack_set_limits(&h->engine,high,high-size);
        Z_EXPORT__emscripten_stack_restore(&h->engine,high);
        Z_EXPORT__emscripten_thread_init(&h->engine,h->pthread,0,0,1,0,0);
        Z_EXPORT__emscripten_tls_init(&h->engine);
        wasm_rt_funcref_table_t *table=Z_EXPORT__indirect_function_table(&h->engine);
        if(w->routine>=table->size)wasm_rt_trap(WASM_RT_TRAP_CALL_INDIRECT);
        wasm_rt_funcref_t f=table->data[w->routine];
        wasm_rt_func_type_t expected=wasm2c_xray_get_func_type(1,1,WASM_RT_I64,WASM_RT_I64);
        if(!f.func||!f.func_type||memcmp(f.func_type,expected,32))wasm_rt_trap(WASM_RT_TRAP_CALL_INDIRECT);
        u64 result=((u64 (*)(void *,u64))f.func)(f.module_instance,w->argument);
        Z_EXPORT__emscripten_thread_exit(&h->engine,result);
    }
    if(h->yield_reason==1) {
        // WasmFS's service thread yields instead of returning. Keep its native
        // instance/TLS alive and run the actual guest proxy queue callbacks.
        while(!atomic_load(&h->runtime->stopping)) {
            wasm_rt_trap_t trap=wasm_rt_impl_try();
            if(trap){fprintf(stderr,"[engine] Parked worker trapped: %s\n",wasm_rt_strerror(trap));atomic_fetch_add(&h->runtime->failures,1);break;}
            z_pump(h);
            struct timespec pause={.tv_nsec=5000000};nanosleep(&pause,NULL);
        }
    }
    // Records remain owned by the process runtime. They cannot be reclaimed
    // while other guest threads may still refer to their TLS/pthread state.
    return NULL;
}
u32 Z_IMPORT___pthread_create_js(struct w2c_a *parent,u64 thread,u64 attr,u64 routine,u64 argument) {
    (void)attr;Worker *w=calloc(1,sizeof *w);if(!w)return 6;
    w->host.runtime=parent->runtime;w->host.pthread=thread;w->host.worker=true;w->routine=routine;w->argument=argument;
    pthread_attr_t attributes;pthread_attr_init(&attributes);pthread_attr_setstacksize(&attributes,16*1024*1024);
    pthread_mutex_lock(&parent->runtime->lock);w->host.next=parent->runtime->threads;parent->runtime->threads=&w->host;pthread_mutex_unlock(&parent->runtime->lock);
    pthread_t native;int e=pthread_create(&native,&attributes,run_worker,w);pthread_attr_destroy(&attributes);
    if(e){fprintf(stderr,"[engine] pthread_create failed: %d\n",e);atomic_fetch_add(&parent->runtime->failures,1);return 6;}
    pthread_detach(native);return 0;
}
void Z_IMPORT_emscripten_sleep(struct w2c_a *h,u32 milliseconds) {
    do {
        u32 slice=milliseconds>20?20:milliseconds;
        struct timespec delay={.tv_nsec=(long)slice*1000000};
        nanosleep(&delay,NULL);zone_native_checkpoint();milliseconds-=slice;
    } while(milliseconds);
    z_pump(h);
}
void Z_IMPORT_emscripten_set_main_loop_arg(struct w2c_a *h,u64 callback,u64 argument,u32 fps,u32 simulate_infinite) {
    (void)fps;h->main_loop=callback;h->main_loop_arg=argument;
    if(simulate_infinite)z_leave(h,1,0);
}
void Z_IMPORT_emscripten_cancel_main_loop(struct w2c_a *h) { h->main_loop=0; }
u32 Z_IMPORT_emscripten_set_main_loop_timing(struct w2c_a *h,u32 mode,u32 value) { (void)mode;(void)value;return h->main_loop?0:1; }
