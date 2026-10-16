#include "ZoneHost.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    ZHostResetInput();
    ZButtonEvent event;
    while (ZHostPollButton(&event)) {}
    /* A tap shorter than a render frame must still deliver both transitions. */
    ZHostSetButton(ZActionJump, true); ZHostSetButton(ZActionJump, false);
    assert(ZHostReadInput().held == 0);
    assert(ZHostPollButton(&event) && event.action == ZActionJump && event.down);
    assert(ZHostPollButton(&event) && event.action == ZActionJump && !event.down);
    assert(!ZHostPollButton(&event));
    ZHostSetMove(INFINITY, -2); ZHostAddLook(10, 3); ZHostAddLook(5, -2);
    ZInput input = ZHostReadInput();
    assert(input.move_x == 0 && input.move_y == -1);
    assert(input.look_x == 15 && input.look_y == 1);
    assert(ZHostReadInput().look_x == 0);
    ZHostSetButton(ZActionFire, true); ZHostResetInput();
    assert(ZHostReadInput().held == 0);
    bool fire_released = false;
    while (ZHostPollButton(&event)) if (event.action == ZActionFire && !event.down) fire_released = true;
    assert(fire_released);
    /* A saturated producer must recover to exactly the current held state. */
    for (unsigned i = 0; i < 2000; ++i) ZHostSetButton(ZActionAim, i % 2 == 0);
    uint64_t state = 0;
    while (ZHostPollButton(&event)) {
        uint64_t bit = UINT64_C(1) << event.action;
        if (event.down) state |= bit; else state &= ~bit;
    }
    assert(state == ZHostReadInput().held && ZHostDroppedInputEvents() > 0);
    assert(ZHostActionScancode(ZActionUse) == 9);
    assert(ZHostMonotonicSeconds() > 0);
    assert(!ZHostEngineAvailable());
    puts("Native input: tap ordering, axis bounds, look consumption, reset and overflow passed.");
}
