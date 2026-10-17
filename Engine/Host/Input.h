#pragma once
#include "Host.h"

enum { ZKeyControl=1,ZKeyShift=2,ZKeyAlt=4,ZKeyMeta=8 };
// Call only on the registered callback's native engine thread. UIKit queues
// native values; it never writes guest TLS or invokes guest functions itself.
bool z_input_key(struct w2c_a *,u32 keycode,const char *key,const char *code,u32 location,bool down,u32 modifiers);
bool z_input_mouse(struct w2c_a *,u32 type,u32 button,u32 buttons,int32_t x,int32_t y,f64 dx,f64 dy);
bool z_input_wheel(struct w2c_a *,u32 buttons,int32_t x,int32_t y,f64 delta);
bool z_input_focus(struct w2c_a *,bool focused);
void z_input_frame_time(struct w2c_a *,f64 milliseconds);
