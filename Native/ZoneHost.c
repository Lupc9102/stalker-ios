#define _POSIX_C_SOURCE 200809L
#include "ZoneHost.h"
#include <pthread.h>
#include <math.h>
#include <time.h>
#include <string.h>

#define QUEUE_SIZE 256u
static pthread_mutex_t input_lock = PTHREAD_MUTEX_INITIALIZER;
static ZInput input;
static ZButtonEvent events[QUEUE_SIZE];
static unsigned read_index, write_index, event_count;
static uint32_t dropped;
static float axis(float value) {
    return isfinite(value) ? fminf(1, fmaxf(-1, value)) : 0;
}
void ZHostSetButton(ZAction action, bool down) {
    if (action < 0 || action >= ZActionCount) return;
    pthread_mutex_lock(&input_lock);
    uint64_t bit = UINT64_C(1) << action;
    if (((input.held & bit) != 0) != down) {
        if (down) input.held |= bit; else input.held &= ~bit;
        if (event_count == QUEUE_SIZE) {
            /* Never leave the engine with a stuck key after overflow: reset the
               queue to a complete release, then replay the current held state. */
            read_index = write_index = event_count = 0;
            ++dropped;
            for (int a = 0; a < ZActionCount; ++a) {
                events[write_index++] = (ZButtonEvent){(ZAction)a, false};
                ++event_count;
            }
            for (int a = 0; a < ZActionCount; ++a) if (input.held & (UINT64_C(1) << a)) {
                events[write_index++] = (ZButtonEvent){(ZAction)a, true};
                ++event_count;
            }
        } else {
            events[write_index] = (ZButtonEvent){action, down};
            write_index = (write_index + 1) % QUEUE_SIZE;
            ++event_count;
        }
    }
    pthread_mutex_unlock(&input_lock);
}
void ZHostSetMove(float x, float y) {
    pthread_mutex_lock(&input_lock);
    input.move_x = axis(x); input.move_y = axis(y);
    pthread_mutex_unlock(&input_lock);
}
void ZHostAddLook(float x, float y) {
    if (!isfinite(x) || !isfinite(y)) return;
    pthread_mutex_lock(&input_lock);
    input.look_x = fminf(10000, fmaxf(-10000, input.look_x + x));
    input.look_y = fminf(10000, fmaxf(-10000, input.look_y + y));
    pthread_mutex_unlock(&input_lock);
}
ZInput ZHostReadInput(void) {
    pthread_mutex_lock(&input_lock);
    ZInput result = input;
    input.look_x = input.look_y = 0;
    pthread_mutex_unlock(&input_lock);
    return result;
}
bool ZHostPollButton(ZButtonEvent *event) {
    if (!event) return false;
    pthread_mutex_lock(&input_lock);
    bool available = event_count != 0;
    if (available) {
        *event = events[read_index]; read_index = (read_index + 1) % QUEUE_SIZE;
        --event_count;
    }
    pthread_mutex_unlock(&input_lock);
    return available;
}
void ZHostResetInput(void) {
    pthread_mutex_lock(&input_lock);
    memset(&input, 0, sizeof input);
    read_index = write_index = event_count = 0;
    /* Releases must reach the engine even if it hasn't consumed earlier presses. */
    for (int a = 0; a < ZActionCount; ++a) {
        events[write_index++] = (ZButtonEvent){(ZAction)a, false}; ++event_count;
    }
    pthread_mutex_unlock(&input_lock);
}
uint32_t ZHostDroppedInputEvents(void) {
    pthread_mutex_lock(&input_lock);
    uint32_t result = dropped;
    pthread_mutex_unlock(&input_lock);
    return result;
}
uint32_t ZHostActionScancode(ZAction action) {
    /* F/R/Space/Ctrl/Shift/I/P/L/O/1/6, Q/E and Escape. Quick slots F1/F2. */
    static const uint32_t keys[ZActionCount] = {
        0, 0, 9, 21, 44, 224, 225, 12, 19, 15, 18, 30, 35, 0,
        58, 59, 20, 8, 41
    };
    return action >= 0 && action < ZActionCount ? keys[action] : 0;
}
double ZHostMonotonicSeconds(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return (double)time.tv_sec + (double)time.tv_nsec / 1e9;
}
bool ZHostEngineAvailable(void) { return false; }
const char *ZHostEngineStatus(void) {
    return "Engine integration in progress. Controls practice is available.";
}
