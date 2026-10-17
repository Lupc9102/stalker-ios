#define _POSIX_C_SOURCE 200809L
#include "Host.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

_Thread_local struct w2c_a *z_current_thread;
wasm_rt_shared_memory_t *w2c_a_a(struct w2c_a *h) { return &h->runtime->memory; }
void *z_pointer(struct w2c_a *h,u64 at,u64 size) {
    wasm_rt_shared_memory_t *m=w2c_a_a(h);
    if(at>m->size || size>m->size-at) wasm_rt_trap(WASM_RT_TRAP_OOB);
    return (unsigned char *)(void *)m->data+at;
}
const char *z_string(struct w2c_a *h,u64 at) {
    if(!at) return "";
    const char *s=z_pointer(h,at,1);
    if(!memchr(s,0,w2c_a_a(h)->size-at)) wasm_rt_trap(WASM_RT_TRAP_OOB);
    return s;
}
void z_write32(struct w2c_a *h,u64 p,u32 v) { memcpy(z_pointer(h,p,4),&v,4); }
void z_write64(struct w2c_a *h,u64 p,u64 v) { memcpy(z_pointer(h,p,8),&v,8); }
u64 z_read64(struct w2c_a *h,u64 p) { u64 v;memcpy(&v,z_pointer(h,p,8),8);return v; }
_Noreturn void z_missing(struct w2c_a *h,const char *name) {
    fprintf(stderr,"[engine] UNIMPLEMENTED: %s (guest thread %llu)\n",name,(unsigned long long)h->pthread);
    unsigned first=0;
    if(atomic_compare_exchange_strong(&h->runtime->first_failure,&first,1)) {
        snprintf(h->runtime->error,sizeof h->runtime->error,"Unsupported engine call: %s",name);
        atomic_store(&h->runtime->error_ready,true);
    }
    atomic_fetch_add(&h->runtime->failures,1);
    wasm_rt_trap(WASM_RT_TRAP_UNREACHABLE);
}
_Noreturn void z_leave(struct w2c_a *h,int reason,int status) {
    h->yield_reason=reason;h->status=status;
#if WASM_RT_STACK_DEPTH_COUNT
    // Emscripten's live-runtime yield unwinds C without function epilogues.
    // Restore the same depth baseline as a caught Wasm runtime trap.
    wasm_rt_call_stack_depth=wasm_rt_saved_call_stack_depth;
#endif
    wasm_rt_set_unwind_target(NULL);
    longjmp(h->yielded,1);
}
static double milliseconds(clockid_t clock) {
    struct timespec t;clock_gettime(clock,&t);return t.tv_sec*1000.0+t.tv_nsec/1000000.0;
}
f64 Z_IMPORT_emscripten_date_now(struct w2c_a *h) { (void)h;return milliseconds(CLOCK_REALTIME); }
f64 Z_IMPORT_emscripten_get_now(struct w2c_a *h) { (void)h;return milliseconds(CLOCK_MONOTONIC); }
u32 Z_IMPORT_emscripten_num_logical_cores(struct w2c_a *h) { (void)h;long n=sysconf(_SC_NPROCESSORS_ONLN);return n>0?(u32)n:1; }
void Z_IMPORT_emscripten_check_blocking_allowed(struct w2c_a *h) { (void)h; /* Native engine threads may block. */ }
u64 Z_IMPORT_emscripten_get_heap_max(struct w2c_a *h) { return w2c_a_a(h)->max_pages*WASM_DEFAULT_PAGE_SIZE; }
u32 Z_IMPORT_emscripten_resize_heap(struct w2c_a *h,u64 desired) {
    // Beyond the configured cap, report ordinary allocation failure. Never
    // relocate memory while another thread or native API retains a pointer.
    return desired<=w2c_a_a(h)->size;
}
void Z_IMPORT_emscripten_out(struct w2c_a *h,u64 p) {
#if WASM_RT_STACK_DEPTH_COUNT
    if(getenv("ZONE_TRACE_STACK"))fprintf(stdout,"[native guest-call depth=%u] ",wasm_rt_call_stack_depth);
#endif
    fprintf(stdout,"%s\n",z_string(h,p));fflush(stdout);
}
void Z_IMPORT_emscripten_err(struct w2c_a *h,u64 p) { fprintf(stderr,"%s\n",z_string(h,p)); }
void Z_IMPORT__emscripten_log_formatted(struct w2c_a *h,u32 flags,u64 p) { (void)flags;Z_IMPORT_emscripten_err(h,p); }
void Z_IMPORT___assert_fail(struct w2c_a *h,u64 condition,u64 file,u32 line,u64 function) {
    fprintf(stderr,"[engine] ASSERT: %s at %s:%u (%s)\n",z_string(h,condition),z_string(h,file),line,z_string(h,function));
    wasm_rt_trap(WASM_RT_TRAP_UNREACHABLE);
}
void Z_IMPORT__abort_js(struct w2c_a *h) { (void)h;fprintf(stderr,"[engine] abort requested\n");wasm_rt_trap(WASM_RT_TRAP_UNREACHABLE); }
void Z_IMPORT_exit(struct w2c_a *h,u32 status) { z_leave(h,2,(int)status); }
void Z_IMPORT_proc_exit(struct w2c_a *h,u32 status) { z_leave(h,2,(int)status); }
void Z_IMPORT_emscripten_force_exit(struct w2c_a *h,u32 status) { z_leave(h,2,(int)status); }
void Z_IMPORT_emscripten_exit_with_live_runtime(struct w2c_a *h) { z_leave(h,1,0); }
void Z_IMPORT_emscripten_unwind_to_js_event_loop(struct w2c_a *h) { z_leave(h,1,0); }
void Z_IMPORT__emscripten_runtime_keepalive_clear(struct w2c_a *h) { (void)h; }
u32 Z_IMPORT_emscripten_runtime_keepalive_check(struct w2c_a *h) { return !atomic_load(&h->runtime->stopping); }
u32 Z_IMPORT_emscripten_has_asyncify(struct w2c_a *h) { (void)h;return 0; }
u32 Z_IMPORT__emscripten_system(struct w2c_a *h,u64 command) { (void)h;return command?(u32)-52:0; }
u32 Z_IMPORT_random_get(struct w2c_a *h,u64 p,u64 bytes) {
    unsigned char *buffer=z_pointer(h,p,bytes);int fd=open("/dev/urandom",O_RDONLY);
    if(fd<0)return 29;
    while(bytes) { ssize_t n=read(fd,buffer,bytes);if(n<0&&errno==EINTR)continue;if(n<=0){close(fd);return 29;}buffer+=n;bytes-=n; }
    close(fd);return 0;
}
u32 Z_IMPORT_environ_sizes_get(struct w2c_a *h,u64 count,u64 bytes) { z_write64(h,count,0);z_write64(h,bytes,0);return 0; }
u32 Z_IMPORT_environ_get(struct w2c_a *h,u64 env,u64 buffer) { (void)h;(void)env;(void)buffer;return 0; }
u32 Z_IMPORT_clock_time_get(struct w2c_a *h,u32 clock,u64 precision,u64 out) {
    (void)precision;if(clock>3)return 28;struct timespec t;
    if(clock_gettime(clock==0?CLOCK_REALTIME:CLOCK_MONOTONIC,&t))return 29;
    z_write64(h,out,(u64)t.tv_sec*1000000000+t.tv_nsec);return 0;
}
static u32 time_to_tm(struct w2c_a *h,u64 seconds,u64 output,bool utc) {
    time_t t=(time_t)seconds;struct tm value;
    if(!(utc?gmtime_r(&t,&value):localtime_r(&t,&value)))return 1;
    u32 fields[]={value.tm_sec,value.tm_min,value.tm_hour,value.tm_mday,value.tm_mon,value.tm_year,value.tm_wday,value.tm_yday,value.tm_isdst};
    memcpy(z_pointer(h,output,sizeof fields),fields,sizeof fields);
    z_write64(h,output+40,utc?0:(u64)value.tm_gmtoff);return 0;
}
u32 Z_IMPORT__gmtime_js(struct w2c_a *h,u64 seconds,u64 output) { return time_to_tm(h,seconds,output,true); }
u32 Z_IMPORT__localtime_js(struct w2c_a *h,u64 seconds,u64 output) { return time_to_tm(h,seconds,output,false); }
u64 Z_IMPORT__mktime_js(struct w2c_a *h,u64 p) {
    u32 f[9];memcpy(f,z_pointer(h,p,sizeof f),sizeof f);
    struct tm t={.tm_sec=(int)f[0],.tm_min=(int)f[1],.tm_hour=(int)f[2],.tm_mday=(int)f[3],.tm_mon=(int)f[4],.tm_year=(int)f[5],.tm_isdst=(int)f[8]};
    time_t seconds=mktime(&t);if(seconds!=(time_t)-1)time_to_tm(h,(u64)seconds,p,false);return (u64)seconds;
}
void Z_IMPORT__tzset_js(struct w2c_a *h,u64 offset,u64 daylight_ptr,u64 standard,u64 summer) {
    tzset();time_t now=time(NULL);struct tm local;localtime_r(&now,&local);
    z_write64(h,offset,(u64)-local.tm_gmtoff);z_write32(h,daylight_ptr,local.tm_isdst>0);
    snprintf(z_pointer(h,standard,17),17,"%s",tzname[0]);snprintf(z_pointer(h,summer,17),17,"%s",tzname[1]);
}
long double z_proxy_argument(struct w2c_a *h,u64 packet,unsigned i,u32 bytes) {
    if((u64)i*16+16>bytes)wasm_rt_trap(WASM_RT_TRAP_OOB);
    u64 tag=z_read64(h,packet+i*16);if(tag)return (long double)z_read64(h,packet+i*16+8);
    double v;memcpy(&v,z_pointer(h,packet+i*16+8,8),8);return v;
}
f64 Z_IMPORT__emscripten_receive_on_main_thread_js(struct w2c_a *h,u32 index,u64 asm_address,u64 caller,u32 bytes,u64 args,u64 ctx,u64 ctx_args) {
    (void)caller;double result;
    if(asm_address) {
        if(bytes%16||bytes/16>16)wasm_rt_trap(WASM_RT_TRAP_OOB);
        long double values[16];for(unsigned i=0;i<bytes/16;i++)values[i]=z_proxy_argument(h,args,i,bytes);
        result=z_asm(h,asm_address,values,bytes/16);
    } else result=z_proxy(h,index,args,bytes);
    if(ctx)Z_EXPORT__emscripten_run_js_on_main_thread_done(&h->engine,ctx,ctx_args,result);
    return result;
}
