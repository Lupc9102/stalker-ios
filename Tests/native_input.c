#include "Input.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned char last[160];static unsigned calls,type;
static u32 capture(void *instance,u32 event,u64 pointer,u64 user) {
    struct w2c_a *h=instance;assert(user==0x12345678);type=event;calls++;
    memcpy(last,z_pointer(h,pointer,160),160);return 1;
}
static int32_t integer(unsigned offset) { int32_t value;memcpy(&value,last+offset,4);return value; }
int main(void) {
    wasm_rt_init();ZRuntime *rt=calloc(1,sizeof *rt);struct w2c_a *h=calloc(1,sizeof *h);assert(rt&&h);
    h->runtime=rt;h->pthread=1234;rt->main_guest_thread=1234;pthread_mutex_init(&rt->lock,NULL);z_current_thread=h;
    assert(z_memory_open(rt,5120));assert(wasm_rt_impl_try()==WASM_RT_TRAP_NONE);
    wasm2c_xray_instantiate(&h->engine,h);w2c_xray_fi(&h->engine);
    wasm_rt_funcref_table_t *table=Z_EXPORT__indirect_function_table(&h->engine);wasm_rt_funcref_t saved=table->data[1];
    table->data[1].func_type=wasm2c_xray_get_func_type(3,1,WASM_RT_I32,WASM_RT_I64,WASM_RT_I64,WASM_RT_I32);
    table->data[1].func=(wasm_rt_function_ptr_t)capture;table->data[1].module_instance=h;
    const u32 types[]={2,3,5,6,8,9};
    for(unsigned i=0;i<6;i++)assert(!z_register_event(h,types[i],0x12345678,1,2,2,true));
    assert(z_input_key(h,87,"w","KeyW",0,true,ZKeyControl|ZKeyShift));
    assert(type==2&&calls==1&&integer(24)==87&&integer(28)==87&&last[12]&&last[13]&&!last[14]);
    assert(!strcmp((char *)last+32,"w")&&!strcmp((char *)last+64,"KeyW"));
    assert(z_input_key(h,87,"w","KeyW",0,false,0)&&type==3&&calls==2&&!last[12]);
    assert(z_input_mouse(h,5,2,2,120,240,0,0)&&type==5&&integer(16)==120&&integer(44)==240);
    uint16_t button;memcpy(&button,last+28,2);assert(button==2);
    rt->mouse_pointer=((u64)1<<32)+8192;rt->mouse_scale=1024;
    assert(z_input_mouse(h,8,0,2,130,250,2.5,-1.25)&&integer(32)==3&&integer(36)==-1);
    int32_t motion[2];memcpy(motion,z_pointer(h,rt->mouse_pointer,8),8);assert(motion[0]==2560&&motion[1]==-1280);
    assert(z_input_wheel(h,0,100,200,-1)&&type==9&&integer(88)==1);
    double delta;memcpy(&delta,last+72,8);assert(delta==-1);
    unsigned before=calls;assert(!z_register_event(h,2,0x12345678,1,5678,2,true));
    assert(!z_input_key(h,87,"w","KeyW",0,true,0)&&calls==before);
    assert(!z_register_event(h,2,0x12345678,1,1,2,true));assert(z_input_key(h,87,"w","KeyW",0,true,0));
    rt->frame_time_pointer=rt->mouse_pointer+16;z_input_frame_time(h,16.6666667);
    u32 time;memcpy(&time,z_pointer(h,rt->frame_time_pointer,4),4);assert(time==16667);
    assert(!z_register_event(h,13,0x12345678,1,2,2,true));
    assert(z_input_focus(h,true)&&type==13&&!strcmp((char *)last,"CANVAS")&&!strcmp((char *)last+128,"canvas"));
    // Removing a document listener must preserve an existing canvas listener.
    // SDL registers these separately; treating the event type as its identity
    // silently removes the actual mouse-down handler during window setup.
    u64 canvas=Z_EXPORT_malloc(&h->engine,16);memcpy(z_pointer(h,canvas,8),"#canvas",8);
    assert(!z_register_event(h,5,0x12345678,1,2,canvas,true));
    assert(!z_register_event(h,5,0,0,2,1,true));
    before=calls;assert(z_input_mouse(h,5,0,1,10,20,0,0)&&calls==before+2);
    assert(!z_register_event(h,5,0,0,2,2,true));
    before=calls;assert(z_input_mouse(h,5,0,1,10,20,0,0)&&calls==before+1);
    assert(!z_register_event(h,5,0,0,2,canvas,true));assert(!z_input_mouse(h,5,0,1,10,20,0,0));
    Z_EXPORT_free(&h->engine,canvas);z_events_close(rt);
    table->data[1]=saved;Z_EXPORT_free(&h->engine,h->input_buffer);wasm2c_xray_free(&h->engine);z_memory_close(rt);
    pthread_mutex_destroy(&rt->lock);free(h);free(rt);wasm_rt_free();
    puts("Engine input: typed guest callbacks, thread ownership, keyboard/mouse/wheel ABI, raw-look accumulation and frame timing passed.");
    return 0;
}
