#pragma once
#include "NativeABI.h"
#include "wasm-rt-impl.h"
#include "Atomics.h"
#include "Diagnostics.h"
#include <stdatomic.h>
#include <pthread.h>
#include <setjmp.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct ZFilesystem ZFilesystem;
typedef struct ZRuntime ZRuntime;
typedef struct ZEvent { u64 callback,user,target,owner;bool capture;struct ZEvent *next; } ZEvent;
struct w2c_a {
    ZRuntime *runtime;
    w2c_xray engine;
    struct w2c_a *next;
    u64 pthread, heartbeat;
    u64 main_loop, main_loop_arg;
    u64 input_buffer;
    u32 input_modifiers;
    jmp_buf yielded;
    int yield_reason, status;
    bool worker;
};
struct ZRuntime {
    wasm_rt_shared_memory_t memory;
    ZFilesystem *files;
    void *audio;
    void *graphics;
    pthread_mutex_t lock;
    struct w2c_a *threads;
    atomic_bool stopping;
    atomic_uint failures;
    atomic_uint first_failure;
    atomic_bool error_ready;
    char error[256];
    u32 width, height;
    bool offline;
    u64 main_guest_thread;
    ZEvent events[64];
    u64 frame_time_pointer, mouse_pointer;
    double mouse_scale;
    bool cursor_visible;
    char window_title[256];
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
wasm_rt_funcref_t z_checked_function(struct w2c_a *, u64, wasm_rt_func_type_t, const char *);
void z_pump(struct w2c_a *);
void z_atomic_wait_pump(void);
u32 z_register_event(struct w2c_a *,u32,u64,u64,u64,u64,bool);
bool z_dispatch_event(struct w2c_a *,u32,u64);
void z_events_close(ZRuntime *);
ZFilesystem *z_files_open(const char *, const char *);
void z_files_close(ZFilesystem *);
bool z_memory_open(ZRuntime *,u32 megabytes);
void z_memory_close(ZRuntime *);
void z_audio_pause(struct w2c_a *,bool);
