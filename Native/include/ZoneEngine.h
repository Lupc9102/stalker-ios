#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

enum { ZEngineIdle,ZEngineStarting,ZEngineRunning,ZEnginePaused,ZEngineEnded,ZEngineFailed };
// frames counts callbacks; cursor is the system cursor, not CoP's drawn UI cursor.
typedef struct { int32_t phase;uint32_t width,height;uint64_t frames;bool cursor; } ZEngineInfo;
// This first integration owns one engine session for the app process. Its
// shared heap and worker records remain alive until the process exits.
bool ZEngineCanStart(void);
bool ZEngineStart(void *caeagl_layer,const char *game,const char *overlay,double view_width,double view_height);
void ZEngineSetPaused(bool);
void ZEngineSetActive(bool);
void ZEngineStop(void);
void ZEngineSetViewSize(double width,double height);
void ZEnginePointer(float x,float y,bool down);
ZEngineInfo ZEngineGetInfo(void);
void ZEngineCopyStatus(char *output,size_t capacity);
