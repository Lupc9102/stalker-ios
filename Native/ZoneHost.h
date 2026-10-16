#ifndef ZONE_HOST_H
#define ZONE_HOST_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

/* Stable interface between UIKit, physical controllers and the engine adapter. */
typedef enum {
    ZActionFire, ZActionAim, ZActionUse, ZActionReload, ZActionJump,
    ZActionCrouch, ZActionSprint, ZActionInventory, ZActionPDA, ZActionTorch,
    ZActionDetector, ZActionKnife, ZActionBolt, ZActionWeaponNext,
    ZActionMedkit, ZActionBandage, ZActionLeanLeft, ZActionLeanRight,
    ZActionPause, ZActionCount
} ZAction;
typedef struct {
    uint64_t held;
    float move_x, move_y;
    float look_x, look_y; /* accumulated relative motion, consumed once */
} ZInput;
typedef struct { ZAction action; bool down; } ZButtonEvent;

void ZHostSetButton(ZAction action, bool down);
void ZHostSetMove(float x, float y);
void ZHostAddLook(float x, float y);
ZInput ZHostReadInput(void);
bool ZHostPollButton(ZButtonEvent *event);
void ZHostResetInput(void);
uint32_t ZHostDroppedInputEvents(void);
/* SDL2 scancodes for a default CoP keyboard binding; mouse buttons return 0. */
uint32_t ZHostActionScancode(ZAction action);
double ZHostMonotonicSeconds(void);
/* The initial app deliberately cannot launch a partially implemented engine. */
bool ZHostEngineAvailable(void);
const char *ZHostEngineStatus(void);
#ifdef __cplusplus
}
#endif
#endif
