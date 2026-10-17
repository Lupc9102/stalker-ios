#include "Host.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
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
static u64 event_target(struct w2c_a *h,u64 target) {
    if(target==1||target==2)return target;
    if(target<=2)return 0;
    const char *name=z_string(h,target);
    if(!strcmp(name,"#canvas")||!strcmp(name,"canvas"))return 3;
    if(!strcmp(name,"#window")||!strcmp(name,"window"))return 2;
    if(!strcmp(name,"#document")||!strcmp(name,"document"))return 1;
    return 0;
}
u32 z_register_event(struct w2c_a *h,u32 type,u64 user,u64 callback,u64 thread,u64 surface,bool capture) {
    if(type>=64)return (u32)-5;
    u64 target=event_target(h,surface);if(!target)return (u32)-4;
    pthread_mutex_lock(&h->runtime->lock);
    ZEvent *slot=&h->runtime->events[type],*empty=NULL;
    while(slot) {
        if(slot->target==target&&slot->capture==capture)break;
        if(!slot->callback&&!empty)empty=slot;
        if(!slot->next) {
            if(!callback){pthread_mutex_unlock(&h->runtime->lock);return 0;}
            if(empty){slot=empty;break;}
            slot->next=calloc(1,sizeof *slot);
            if(!slot->next){pthread_mutex_unlock(&h->runtime->lock);return (u32)-6;}
        }
        slot=slot->next;
    }
    u64 owner=thread>2?thread:(thread==1?h->runtime->main_guest_thread:h->pthread);
    ZEvent *next=slot->next;*slot=(ZEvent){.callback=callback,.user=user,.target=target,.owner=owner,.capture=capture,.next=next};
    if(getenv("ZONE_TRACE_EVENTS"))fprintf(stderr,"[engine] Event %u target=%llu capture=%d callback=%llu owner=%llu\n",type,(unsigned long long)target,capture,(unsigned long long)callback,(unsigned long long)owner);
    pthread_mutex_unlock(&h->runtime->lock);return 0;
}
bool z_dispatch_event(struct w2c_a *h,u32 type,u64 event) {
    if(type>=64)return false;
    ZEvent registered[8];unsigned count=0;
    pthread_mutex_lock(&h->runtime->lock);
    for(ZEvent *slot=&h->runtime->events[type];slot;slot=slot->next)if(slot->callback&&slot->owner==h->pthread) {
        if(count>=8){pthread_mutex_unlock(&h->runtime->lock);z_missing(h,"too many native surface event handlers");}
        registered[count++]=*slot;
    }
    pthread_mutex_unlock(&h->runtime->lock);
    // Called by the owning native engine thread with a validated guest event
    // structure. UI callbacks must enqueue there; they cannot mutate guest TLS.
    wasm_rt_funcref_table_t *table=Z_EXPORT__indirect_function_table(&h->engine);
    wasm_rt_func_type_t expected=wasm2c_xray_get_func_type(3,1,WASM_RT_I32,WASM_RT_I64,WASM_RT_I64,WASM_RT_I32);
    bool handled=false;
    for(int capture=1;capture>=0;capture--)for(unsigned i=0;i<count;i++) {
        ZEvent reg=registered[i];if(reg.capture!=(bool)capture)continue;
        if(reg.callback>=table->size)wasm_rt_trap(WASM_RT_TRAP_CALL_INDIRECT);
        wasm_rt_funcref_t f=table->data[reg.callback];
        if(!f.func||!f.func_type||memcmp(f.func_type,expected,32))wasm_rt_trap(WASM_RT_TRAP_CALL_INDIRECT);
        handled|=((u32 (*)(void *,u32,u64,u64))f.func)(f.module_instance,type,event,reg.user)!=0;
    }
    return handled;
}
void z_events_close(ZRuntime *runtime) {
    for(unsigned i=0;i<64;i++) {
        ZEvent *slot=runtime->events[i].next;
        while(slot){ZEvent *next=slot->next;free(slot);slot=next;}
        runtime->events[i]=(ZEvent){0};
    }
}
