#pragma once
#include "NativeABI.h"
#include "wasm-rt-impl.h"
#include <stdatomic.h>
#include <pthread.h>
#include <setjmp.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct ZFilesystem ZFilesystem;
typedef struct ZRuntime ZRuntime;
typedef struct { u64 callback, user, target, owner; } ZEvent;
struct w2c_a {
    ZRuntime *runtime;
    w2c_xray engine;
    struct w2c_a *next;
    u64 pthread, heartbeat;
    u64 main_loop, main_loop_arg;
    jmp_buf yielded;
    int yield_reason, status;
    bool worker;
};
struct ZRuntime {
    wasm_rt_shared_memory_t memory;
    ZFilesystem *files;
    void *audio;
    pthread_mutex_t lock;
    struct w2c_a *threads;
    atomic_bool stopping;
    atomic_uint failures;
    u32 width, height;
    ZEvent events[64];
    u64 frame_time_pointer, mouse_pointer;
    double mouse_scale;
};
extern _Thread_local struct w2c_a *z_current_thread;
void *z_pointer(struct w2c_a *, u64, u64);
const char *z_string(struct w2c_a *, u64);
void z_write32(struct w2c_a *, u64, u32);
void z_write64(struct w2c_a *, u64, u64);
u64 z_read64(struct w2c_a *, u64);
_Noreturn void z_missing(struct w2c_a *, const char *);
_Noreturn void z_leave(struct w2c_a *, int, int);
double z_proxy(struct w2c_a *, u32, u64, u32);
long double z_proxy_argument(struct w2c_a *, u64, unsigned, u32);
u32 z_asm(struct w2c_a *,u64,const long double *,unsigned);
void z_call_void(struct w2c_a *, u64, u64);
void z_pump(struct w2c_a *);
void z_atomic_wait_pump(void);
u32 z_register_event(struct w2c_a *,u32,u64,u64,u64);
bool z_dispatch_event(struct w2c_a *,u32,u64);
ZFilesystem *z_files_open(const char *, const char *);
void z_files_close(ZFilesystem *);
