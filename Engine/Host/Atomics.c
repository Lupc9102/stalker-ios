#define _DARWIN_C_SOURCE 1
#define _POSIX_C_SOURCE 200809L
// Adapted from GTA V iOS Port (MIT); see Licenses/GTA-iOS-MIT.txt.
#include "Atomics.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <errno.h>
#include <time.h>

// One queue shared by all instances of a module's imported shared memory.
// Per-waiter condition variables let notify wake exactly the requested count.
typedef struct Waiter {
  const void *address;
  bool notified;
  pthread_cond_t condition;
  struct Waiter *next;
} Waiter;

static pthread_mutex_t queueLock = PTHREAD_MUTEX_INITIALIZER;
static Waiter *waiters;
_Thread_local ZoneCheckpoint zone_native_checkpoint_handler;
_Thread_local void *zone_native_checkpoint_context;
_Thread_local uint32_t zone_native_checkpoint_counter;
void zone_native_checkpoint(void) {
  if(zone_native_checkpoint_handler)zone_native_checkpoint_handler(zone_native_checkpoint_context);
}

static void *checkedAddress(wasm_rt_shared_memory_t *memory, uint64_t offset,
                            uint32_t width) {
  if (offset % width) wasm_rt_trap(WASM_RT_TRAP_UNALIGNED);
  if (offset > memory->size || memory->size - offset < width)
    wasm_rt_trap(WASM_RT_TRAP_OOB);
  return (uint8_t *)(void *)memory->data + offset;
}

static uint32_t waitFor(wasm_rt_shared_memory_t *memory, uint64_t offset,
                        uint64_t expected, uint64_t timeoutBits, uint32_t width) {
  void *address = checkedAddress(memory, offset, width);
  pthread_mutex_lock(&queueLock);
  uint64_t value = width == 4 ? atomic_load((_Atomic uint32_t *)address)
                              : atomic_load((_Atomic uint64_t *)address);
  if (value != expected) {
    pthread_mutex_unlock(&queueLock);
    return 1;
  }
  int64_t timeout = (int64_t)timeoutBits;
  if (!timeout) {
    pthread_mutex_unlock(&queueLock);
    return 2;
  }
  Waiter waiter = {.address = address, .notified = false, .next = waiters};
#ifdef __APPLE__
  pthread_cond_init(&waiter.condition, NULL);
#else
  pthread_condattr_t attr;
  pthread_condattr_init(&attr);
  pthread_condattr_setclock(&attr, CLOCK_MONOTONIC);
  pthread_cond_init(&waiter.condition, &attr);
  pthread_condattr_destroy(&attr);
#endif
  waiters = &waiter;
  struct timespec deadline;
  if (timeout > 0) {
    clock_gettime(CLOCK_MONOTONIC, &deadline);
    deadline.tv_sec += timeout / 1000000000;
    deadline.tv_nsec += timeout % 1000000000;
    if (deadline.tv_nsec >= 1000000000) {
      deadline.tv_sec++;
      deadline.tv_nsec -= 1000000000;
    }
  }
  int result = 0;
  while (!waiter.notified && !result) {
    if (timeout < 0 && !zone_native_checkpoint_handler) {
      result = pthread_cond_wait(&waiter.condition, &queueLock);
    } else {
      // Apple's relative wait uses monotonic time, so wall-clock changes cannot
      // extend or shorten an engine sleep. Recalculate after a spurious wakeup.
      struct timespec now, remaining;
      clock_gettime(CLOCK_MONOTONIC, &now);
      if(timeout<0){remaining.tv_sec=0;remaining.tv_nsec=20000000;}
      else {remaining.tv_sec = deadline.tv_sec - now.tv_sec;remaining.tv_nsec = deadline.tv_nsec - now.tv_nsec;}
      if (remaining.tv_nsec < 0) { remaining.tv_sec--; remaining.tv_nsec += 1000000000; }
      if (remaining.tv_sec < 0) result = ETIMEDOUT;
      else {
        bool quantum=zone_native_checkpoint_handler&&(remaining.tv_sec>0||remaining.tv_nsec>20000000||timeout<0);
        if(quantum){remaining.tv_sec=0;remaining.tv_nsec=20000000;}
#ifdef __APPLE__
        result = pthread_cond_timedwait_relative_np(&waiter.condition, &queueLock, &remaining);
#else
        struct timespec until={now.tv_sec+remaining.tv_sec,now.tv_nsec+remaining.tv_nsec};
        if(until.tv_nsec>=1000000000){until.tv_sec++;until.tv_nsec-=1000000000;}
        result = pthread_cond_timedwait(&waiter.condition, &queueLock, &until);
#endif
        if(result==ETIMEDOUT&&quantum)result=0;
      }
    }
    if(!result&&!waiter.notified&&zone_native_checkpoint_handler) {
      // The waiter remains registered while the engine pauses. Release the
      // queue mutex so another thread can notify it during that pause.
      pthread_mutex_unlock(&queueLock);zone_native_checkpoint();pthread_mutex_lock(&queueLock);
    }
  }
  Waiter **link = &waiters;
  while (*link != &waiter) link = &(*link)->next;
  *link = waiter.next;
  bool notified = waiter.notified;
  pthread_mutex_unlock(&queueLock);
  pthread_cond_destroy(&waiter.condition);
  return notified ? 0 : 2;
}

uint32_t zone_atomic_wait32(wasm_rt_shared_memory_t *m, uint64_t a, uint32_t v,
                           uint64_t timeout) { return waitFor(m, a, v, timeout, 4); }
uint32_t zone_atomic_wait64(wasm_rt_shared_memory_t *m, uint64_t a, uint64_t v,
                           uint64_t timeout) { return waitFor(m, a, v, timeout, 8); }

uint32_t zone_atomic_notify(wasm_rt_shared_memory_t *m, uint64_t offset,
                           uint32_t count) {
  void *address = checkedAddress(m, offset, 4);
  uint32_t total = 0;
  pthread_mutex_lock(&queueLock);
  for (Waiter *w = waiters; w && total < count; w = w->next) {
    if (w->address == address && !w->notified) {
      w->notified = true;
      pthread_cond_signal(&w->condition);
      total++;
    }
  }
  pthread_mutex_unlock(&queueLock);
  return total;
}
