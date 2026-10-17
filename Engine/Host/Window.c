#include "Host.h"
#include <string.h>
#include <stdio.h>
#if defined(ZONE_NATIVE_GLES)
#include "Graphics.h"
#endif

// Dimensions belong to the native surface configuration. These functions do
// not create a context or claim that any graphics operation has succeeded.
void Z_IMPORT_emscripten_get_screen_size(struct w2c_a *h,u64 width,u64 height) {
    z_write32(h,width,h->runtime->width);z_write32(h,height,h->runtime->height);
}
f64 Z_IMPORT_emscripten_get_device_pixel_ratio(struct w2c_a *h) { (void)h;return 1; }
u32 Z_IMPORT_emscripten_set_canvas_element_size(struct w2c_a *h,u64 target,u32 width,u32 height) {
    (void)target;if(!width||!height||width>16384||height>16384)return (u32)-5;
#if defined(ZONE_NATIVE_GLES)
    if(!z_gl_resize(h,width,height))return (u32)-6;
#endif
    h->runtime->width=width;h->runtime->height=height;return 0;
}
u32 Z_IMPORT_emscripten_get_element_css_size(struct w2c_a *h,u64 target,u64 width,u64 height) {
    (void)target;double w=h->runtime->width,v=h->runtime->height;
    memcpy(z_pointer(h,width,8),&w,8);memcpy(z_pointer(h,height,8),&v,8);return 0;
}
u32 Z_IMPORT_emscripten_set_element_css_size(struct w2c_a *h,u64 target,f64 width,f64 height) {
    (void)h;(void)target;(void)width;(void)height;
    // There is no DOM/CSS layout on a native surface.
    return (u32)-1;
}
u32 Z_IMPORT_emscripten_get_num_gamepads(struct w2c_a *h) { (void)h;return 0; }
u32 Z_IMPORT_emscripten_sample_gamepad_data(struct w2c_a *h) { (void)h;return 0; }
u32 Z_IMPORT_emscripten_get_gamepad_status(struct w2c_a *h,u32 index,u64 status) {
    (void)h;(void)index;(void)status;return (u32)-7; // No connected gamepad.
}
u32 Z_IMPORT_emscripten_request_pointerlock(struct w2c_a *h,u64 target,u32 defer) {
    (void)h;(void)target;(void)defer;return (u32)-1; // Native touch surface has no browser pointer lock.
}
u32 Z_IMPORT_emscripten_exit_pointerlock(struct w2c_a *h) { (void)h;return (u32)-1; }
void Z_IMPORT_emscripten_set_window_title(struct w2c_a *h,u64 title) {
    snprintf(h->runtime->window_title,sizeof h->runtime->window_title,"%s",z_string(h,title));
}
u32 z_register_event(struct w2c_a *h,u32 type,u64 user,u64 callback,u64 target) {
    if(type>=64)return (u32)-5;
    pthread_mutex_lock(&h->runtime->lock);
    u64 owner=target>2?target:(target==1?h->runtime->main_guest_thread:h->pthread);
    h->runtime->events[type]=(ZEvent){.callback=callback,.user=user,.target=target,.owner=owner};
    pthread_mutex_unlock(&h->runtime->lock);return 0;
}
bool z_dispatch_event(struct w2c_a *h,u32 type,u64 event) {
    if(type>=64)return false;
    pthread_mutex_lock(&h->runtime->lock);ZEvent reg=h->runtime->events[type];pthread_mutex_unlock(&h->runtime->lock);
    if(!reg.callback||reg.owner!=h->pthread)return false;
    // Called by the owning native engine thread with a validated guest event
    // structure. UI callbacks must enqueue there; they cannot mutate guest TLS.
    wasm_rt_funcref_table_t *table=Z_EXPORT__indirect_function_table(&h->engine);
    if(reg.callback>=table->size)wasm_rt_trap(WASM_RT_TRAP_CALL_INDIRECT);
    wasm_rt_funcref_t f=table->data[reg.callback];
    wasm_rt_func_type_t expected=wasm2c_xray_get_func_type(3,1,WASM_RT_I32,WASM_RT_I64,WASM_RT_I64,WASM_RT_I32);
    if(!f.func||!f.func_type||memcmp(f.func_type,expected,32))wasm_rt_trap(WASM_RT_TRAP_CALL_INDIRECT);
    return ((u32 (*)(void *,u32,u64,u64))f.func)(f.module_instance,type,event,reg.user)!=0;
}
