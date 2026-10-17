#include "Input.h"
#include <math.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>

static unsigned char *event_buffer(struct w2c_a *h) {
    if(!h->input_buffer)h->input_buffer=Z_EXPORT_malloc(&h->engine,256);
    if(!h->input_buffer)wasm_rt_trap(WASM_RT_TRAP_EXHAUSTION);
    unsigned char *event=z_pointer(h,h->input_buffer,256);memset(event,0,256);
    double timestamp=Z_IMPORT_emscripten_get_now(h);memcpy(event,&timestamp,8);return event;
}
static void integer(unsigned char *event,unsigned offset,int32_t value) { memcpy(event+offset,&value,4); }
static int32_t rounded(double value) { return (int32_t)round(fmax(INT32_MIN,fmin(INT32_MAX,value))); }
bool z_input_key(struct w2c_a *h,u32 keycode,const char *key,const char *code,u32 location,bool down,u32 modifiers) {
    h->input_modifiers=modifiers&15;
    unsigned char *event=event_buffer(h);integer(event,8,location);
    event[12]=(modifiers&ZKeyControl)!=0;event[13]=(modifiers&ZKeyShift)!=0;
    event[14]=(modifiers&ZKeyAlt)!=0;event[15]=(modifiers&ZKeyMeta)!=0;
    integer(event,24,keycode);integer(event,28,keycode);
    snprintf((char *)event+32,32,"%s",key);snprintf((char *)event+64,32,"%s",code);
    return z_dispatch_event(h,down?2:3,h->input_buffer);
}
static unsigned char *mouse_buffer(struct w2c_a *h,u32 button,u32 buttons,int32_t x,int32_t y,double dx,double dy) {
    unsigned char *event=event_buffer(h);
    event[24]=(h->input_modifiers&ZKeyControl)!=0;event[25]=(h->input_modifiers&ZKeyShift)!=0;
    event[26]=(h->input_modifiers&ZKeyAlt)!=0;event[27]=(h->input_modifiers&ZKeyMeta)!=0;
    integer(event,8,x);integer(event,12,y);integer(event,16,x);integer(event,20,y);
    uint16_t b=button,held=buttons;memcpy(event+28,&b,2);memcpy(event+30,&held,2);
    integer(event,32,rounded(dx));integer(event,36,rounded(dy));integer(event,40,x);integer(event,44,y);
    return event;
}
bool z_input_mouse(struct w2c_a *h,u32 type,u32 button,u32 buttons,int32_t x,int32_t y,double dx,double dy) {
    if((type!=5&&type!=6&&type!=8&&type!=33&&type!=34)||button>4||buttons>31||!isfinite(dx)||!isfinite(dy))return false;
    mouse_buffer(h,button,buttons,x,y,dx,dy);
    if(type==8&&h->runtime->mouse_pointer) {
        u64 pointer=h->runtime->mouse_pointer;if(pointer%4)wasm_rt_trap(WASM_RT_TRAP_UNALIGNED);
        _Atomic u32 *motion=z_pointer(h,pointer,8);
        double scale=h->runtime->mouse_scale;
        if(isfinite(scale)) {
            atomic_fetch_add_explicit(motion,(u32)rounded(dx*scale),memory_order_relaxed);
            atomic_fetch_add_explicit(motion+1,(u32)rounded(dy*scale),memory_order_relaxed);
        }
    }
    return z_dispatch_event(h,type,h->input_buffer);
}
bool z_input_wheel(struct w2c_a *h,u32 buttons,int32_t x,int32_t y,double delta) {
    if(buttons>31||!isfinite(delta))return false;
    unsigned char *event=mouse_buffer(h,0,buttons,x,y,0,0);
    memcpy(event+72,&delta,8);integer(event,88,1); // DOM_DELTA_LINE.
    return z_dispatch_event(h,9,h->input_buffer);
}
void z_input_frame_time(struct w2c_a *h,double milliseconds) {
    if(!h->runtime->frame_time_pointer||!isfinite(milliseconds)||milliseconds<=0)return;
    u64 pointer=h->runtime->frame_time_pointer;if(pointer%4)wasm_rt_trap(WASM_RT_TRAP_UNALIGNED);
    u32 microseconds=(u32)rounded(fmin(milliseconds,1000)*1000);
    atomic_store_explicit((_Atomic u32 *)z_pointer(h,pointer,4),microseconds,memory_order_relaxed);
}
bool z_input_focus(struct w2c_a *h,bool focused) {
    unsigned char *event=event_buffer(h);memset(event,0,256);
    memcpy(event,"CANVAS",7);memcpy(event+128,"canvas",7);
    return z_dispatch_event(h,focused?13:12,h->input_buffer);
}
