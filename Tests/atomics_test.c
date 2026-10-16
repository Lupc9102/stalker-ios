#define _POSIX_C_SOURCE 200809L
#include "Atomics.h"
#include "SharedSIMD.h"
#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <time.h>

static wasm_rt_shared_memory_t memory;
static _Atomic unsigned started;
static void *waiter(void *unused) {
    (void)unused;
    atomic_fetch_add(&started, 1);
    return (void *)(uintptr_t)(1 + zone_atomic_wait32(&memory, 0, 42, UINT64_C(1000000000)));
}
int main(void) {
    wasm_rt_init();
    wasm_rt_allocate_memory_shared(&memory, 1, 2, true, WASM_DEFAULT_PAGE_SIZE);
    atomic_store((_Atomic uint32_t *)(void *)memory.data, 42);
    assert(zone_atomic_wait32(&memory, 0, 41, 0) == 1);
    assert(zone_atomic_wait32(&memory, 0, 42, 0) == 2);
    assert(zone_atomic_wait32(&memory, 0, 42, 1000000) == 2);
    assert(zone_atomic_wait64(&memory, 8, 0, 0) == 2);
    assert(zone_atomic_notify(&memory, 0, 0) == 0);
    pthread_t threads[2];
    assert(pthread_create(&threads[0], NULL, waiter, NULL) == 0);
    assert(pthread_create(&threads[1], NULL, waiter, NULL) == 0);
    unsigned notified = 0;
    for (int attempt = 0; attempt < 500 && notified < 2; ++attempt) {
        if (atomic_load(&started) == 2) notified += zone_atomic_notify(&memory, 0, 1);
        struct timespec delay = {0, 1000000}; nanosleep(&delay, NULL);
    }
    assert(notified == 2);
    for (int i = 0; i < 2; ++i) { void *result; pthread_join(threads[i], &result); assert((uintptr_t)result == 1); }
    uint8_t bytes[16]; for (int i = 0; i < 16; ++i) bytes[i] = (uint8_t)(10 + i);
    v128 vector = simde_wasm_v128_load(bytes);
    v128_store_shared(NULL, 0, &memory, 101, vector); /* unaligned SIMD is valid */
    simde_wasm_v128_store(bytes, v128_load_shared(NULL, 0, &memory, 101));
    for (int i = 0; i < 16; ++i) assert(bytes[i] == 10 + i);
    vector = zone_v128_load32_zero_shared(NULL, 0, &memory, 101);
    simde_wasm_v128_store(bytes, vector);
    assert(bytes[0] == 10 && bytes[3] == 13);
    for (int i = 4; i < 16; ++i) assert(bytes[i] == 0);
    vector = zone_v128_load16_lane3_shared(NULL, 0, &memory, 105, vector);
    zone_v128_store16_lane3_shared(NULL, 0, &memory, 201, vector);
    assert(atomic_load(memory.data + 201) == 14 && atomic_load(memory.data + 202) == 15);
    wasm_rt_free_memory_shared(&memory); wasm_rt_free();
    puts("Wasm host: timeout, mismatch, two waiters, exact notify count and unaligned SIMD passed.");
}
