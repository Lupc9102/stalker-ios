#if defined(ZONE_WITH_ENGINE)
#import <Foundation/Foundation.h>
#include "ZoneEngine.h"
#include "ZoneHost.h"
#include "Host.h"
#include "Graphics.h"
#include "Input.h"
#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <TargetConditionals.h>
#include <fcntl.h>
#include <unistd.h>

typedef struct { float x,y;bool down; } Pointer;
typedef struct {
    ZRuntime *runtime;struct w2c_a *host;
    char *game,*overlay;
    pthread_t thread;pthread_mutex_t lock;pthread_cond_t changed;
    atomic_uint pause_flags;atomic_bool stopped;
    atomic_int phase;atomic_uint width,height;atomic_ullong frames;atomic_bool cursor;
    _Atomic double view_width,view_height;
    bool pause_ack;char status[256];
    Pointer pointers[256];unsigned pointer_count;bool reset_pointer;
    ZButtonEvent pending[512];unsigned pending_count;
    uint64_t action_held;bool movement[4],pointer_down;u32 mouse_buttons;
    int32_t mouse_x,mouse_y;
} Session;
static _Atomic(Session *) current_session;
static void native_log_setup(void) {
    NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/engine-native.log"];
    int file=open(path.fileSystemRepresentation,O_WRONLY|O_CREAT|O_APPEND,0600);
    if(file>=0){fflush(stdout);fflush(stderr);dup2(file,STDOUT_FILENO);dup2(file,STDERR_FILENO);close(file);}
    setvbuf(stdout,NULL,_IONBF,0);setvbuf(stderr,NULL,_IONBF,0);
    fprintf(stderr,"[native app] Native logging enabled (%s)\n",TARGET_OS_SIMULATOR?"iOS simulator":"physical iOS device");
}
#if TARGET_OS_SIMULATOR
static bool smoke_setup(void) {
    if(![NSProcessInfo.processInfo.arguments containsObject:@"--engine-smoke-test"])return false;
    setenv("ZONE_TRACE_EVENTS","1",1);
    return true;
}
static void smoke_frame(Session *s) {
    u32 width=s->runtime->width,height=s->runtime->height;
    if(!width||!height||width>4096||height>4096)return;
    unsigned char *pixels=calloc((size_t)width*height,4);if(!pixels)return;
    GLint read,pack,alignment,row,skip_rows,skip_pixels;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&read);glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING,&pack);
    glGetIntegerv(GL_PACK_ALIGNMENT,&alignment);glGetIntegerv(GL_PACK_ROW_LENGTH,&row);
    glGetIntegerv(GL_PACK_SKIP_ROWS,&skip_rows);glGetIntegerv(GL_PACK_SKIP_PIXELS,&skip_pixels);
    GLenum previous=glGetError();
    glBindFramebuffer(GL_READ_FRAMEBUFFER,z_gl_framebuffer(s->host,0));glBindBuffer(GL_PIXEL_PACK_BUFFER,0);
    glPixelStorei(GL_PACK_ALIGNMENT,1);glPixelStorei(GL_PACK_ROW_LENGTH,0);
    glPixelStorei(GL_PACK_SKIP_ROWS,0);glPixelStorei(GL_PACK_SKIP_PIXELS,0);
    glReadPixels(0,0,width,height,GL_RGBA,GL_UNSIGNED_BYTE,pixels);GLenum error=glGetError();
    glBindFramebuffer(GL_READ_FRAMEBUFFER,read);glBindBuffer(GL_PIXEL_PACK_BUFFER,pack);
    glPixelStorei(GL_PACK_ALIGNMENT,alignment);glPixelStorei(GL_PACK_ROW_LENGTH,row);
    glPixelStorei(GL_PACK_SKIP_ROWS,skip_rows);glPixelStorei(GL_PACK_SKIP_PIXELS,skip_pixels);
    unsigned lit=0,transparent=0;for(size_t i=0;i<(size_t)width*height;i++){if(pixels[4*i]||pixels[4*i+1]||pixels[4*i+2])lit++;if(!pixels[4*i+3])transparent++;}
    fprintf(stderr,"[native app] framebuffer: cursor=%d lit=%u/%u transparent=%u previousGL=0x%x readGL=0x%x\n",s->runtime->cursor_visible,lit,width*height,transparent,previous,error);
    NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/engine-frame.ppm"];
    FILE *file=fopen(path.fileSystemRepresentation,"wb");
    if(file){fprintf(file,"P6\n%u %u\n255\n",width,height);for(u32 y=height;y>0;y--)for(u32 x=0;x<width;x++)fwrite(pixels+((size_t)(y-1)*width+x)*4,1,3,file);fclose(file);}
    free(pixels);
}
#endif
static void status(Session *s,int phase,const char *message) {
    pthread_mutex_lock(&s->lock);snprintf(s->status,sizeof s->status,"%s",message);
    atomic_store(&s->phase,phase);pthread_cond_broadcast(&s->changed);pthread_mutex_unlock(&s->lock);
}
static void checkpoint(void *pointer) {
    Session *s=pointer;
    if(!atomic_load(&s->pause_flags)&&!atomic_load(&s->stopped))return;
    bool resume_context=Z_IMPORT_emscripten_webgl_get_current_context(s->host)==1;
    z_audio_pause(s->host,true);z_gl_suspend(s->host);
    pthread_mutex_lock(&s->lock);s->pause_ack=true;pthread_cond_broadcast(&s->changed);
    while(atomic_load(&s->pause_flags)||atomic_load(&s->stopped))pthread_cond_wait(&s->changed,&s->lock);
    s->pause_ack=false;pthread_mutex_unlock(&s->lock);
    if(resume_context&&!z_gl_resume(s->host))z_missing(s->host,"iOS GLES context could not resume");
    z_audio_pause(s->host,false);
}
static u32 modifiers(Session *s) { return s->action_held&(UINT64_C(1)<<ZActionCrouch)?ZKeyControl:0; }
typedef struct { u32 key;const char *name,*code;u32 location; } Key;
static const Key action_keys[ZActionCount]={
    {0,"","",0},{0,"","",0},{70,"f","KeyF",0},{82,"r","KeyR",0},{32," ","Space",0},
    {17,"Control","ControlLeft",1},{88,"x","KeyX",0},{73,"i","KeyI",0},{80,"p","KeyP",0},
    {76,"l","KeyL",0},{79,"o","KeyO",0},{49,"1","Digit1",0},{54,"6","Digit6",0},
    {89,"y","KeyY",0},{112,"F1","F1",0},{113,"F2","F2",0},{81,"q","KeyQ",0},
    {69,"e","KeyE",0},{27,"Escape","Escape",0}
};
static void mouse_buttons(Session *s) {
    u32 next=(s->pointer_down?1:0)|((s->action_held&(UINT64_C(1)<<ZActionFire))?1:0)|
        ((s->action_held&(UINT64_C(1)<<ZActionAim))?2:0);
    u32 changed=next^s->mouse_buttons;s->mouse_buttons=next;
    if(changed&1)z_input_mouse(s->host,next&1?5:6,0,next,s->mouse_x,s->mouse_y,0,0);
    if(changed&2)z_input_mouse(s->host,next&2?5:6,2,next,s->mouse_x,s->mouse_y,0,0);
}
static void action(Session *s,ZButtonEvent event) {
    if(event.action<0||event.action>=ZActionCount)return;
    uint64_t bit=UINT64_C(1)<<event.action;
    if(((s->action_held&bit)!=0)==event.down)return;
    if(event.down)s->action_held|=bit;else s->action_held&=~bit;
    const Key *key=action_keys+event.action;
    if(key->key)z_input_key(s->host,key->key,key->name,key->code,key->location,event.down,modifiers(s));
    else mouse_buttons(s);
}
static void input_frame(Session *s) {
    struct w2c_a *h=s->host;ZInput input=ZHostReadInput();ZButtonEvent event;
    while(s->pending_count<512&&ZHostPollButton(&event))s->pending[s->pending_count++]=event;
    // Preserve a short tap across an actual engine frame. The edge after a
    // press is consumed on the following frame instead of cancelling it out.
    uint64_t seen=0;unsigned retained=0;
    for(unsigned i=0;i<s->pending_count;i++) {
        event=s->pending[i];uint64_t bit=UINT64_C(1)<<event.action;
        if(seen&bit)s->pending[retained++]=event;else {seen|=bit;action(s,event);}
    }
    s->pending_count=retained;
    static const Key movement_keys[]={{87,"w","KeyW",0},{83,"s","KeyS",0},{65,"a","KeyA",0},{68,"d","KeyD",0}};
    const float amount[]={input.move_y,-input.move_y,-input.move_x,input.move_x};
    for(unsigned i=0;i<4;i++) {
        bool down=amount[i]>(s->movement[i]?0.2f:0.35f);
        if(down!=s->movement[i]) {const Key *key=movement_keys+i;s->movement[i]=down;z_input_key(h,key->key,key->name,key->code,0,down,modifiers(s));}
    }
    Pointer pointers[256];unsigned count;bool reset;
    pthread_mutex_lock(&s->lock);count=s->pointer_count;memcpy(pointers,s->pointers,count*sizeof *pointers);
    s->pointer_count=0;reset=s->reset_pointer;s->reset_pointer=false;pthread_mutex_unlock(&s->lock);
    if(reset){s->pointer_down=false;mouse_buttons(s);}
    for(unsigned i=0;i<count;i++) {
        int32_t x=(int32_t)round(pointers[i].x*(h->runtime->width-1)),y=(int32_t)round(pointers[i].y*(h->runtime->height-1));
        z_input_mouse(h,8,0,s->mouse_buttons,x,y,x-s->mouse_x,y-s->mouse_y);s->mouse_x=x;s->mouse_y=y;
        s->pointer_down=pointers[i].down;mouse_buttons(s);
    }
    if(input.look_x||input.look_y) {
        double width=fmax(1,atomic_load(&s->view_width)),height=fmax(1,atomic_load(&s->view_height));
        z_input_mouse(h,8,0,s->mouse_buttons,s->mouse_x,s->mouse_y,input.look_x*h->runtime->width/width,input.look_y*h->runtime->height/height);
    }
}
static void fail(Session *s,const char *message) {
    fprintf(stderr,"[native app] Engine failure: %s; frames=%llu; guest-thread=%llu\n",message,
        (unsigned long long)atomic_load(&s->frames),(unsigned long long)s->host->pthread);
    if(zone_indirect_detail[0])fprintf(stderr,"[native app] Last rejected call: %s\n",zone_indirect_detail);
    zone_diagnostic_backtrace("engine failure");
    z_audio_pause(s->host,true);z_gl_suspend(s->host);atomic_store(&s->runtime->stopping,true);
    if(atomic_load(&s->runtime->error_ready))message=s->runtime->error;
    status(s,ZEngineFailed,message);
}
static void *run(void *pointer) {
    @autoreleasepool {
        Session *s=pointer;struct w2c_a *h=s->host;z_current_thread=h;wasm_rt_init_thread();
        #if TARGET_OS_SIMULATOR
        bool smoke=smoke_setup();
        #endif
        zone_native_checkpoint_handler=checkpoint;zone_native_checkpoint_context=s;
        pthread_setname_np("Zone native engine");
        fprintf(stderr,"[native app] Opening game filesystem\n");
        s->runtime->files=z_files_open(s->game,s->overlay);
        if(!s->runtime->files){fail(s,"The selected game folder or writable app-data folder could not be opened.");return NULL;}
        fprintf(stderr,"[native app] Reserving 2048 MiB guest heap\n");
        if(!z_memory_open(s->runtime,2048)){fail(s,"The engine could not reserve its native heap.");return NULL;}
        if(setjmp(h->yielded)==0) {
            wasm_rt_trap_t trap=wasm_rt_impl_try();
            if(trap){fail(s,wasm_rt_strerror(trap));return NULL;}
            fprintf(stderr,"[native app] Instantiating native engine and static constructors\n");
            wasm2c_xray_instantiate(&h->engine,h);w2c_xray_fi(&h->engine);
            #if TARGET_OS_SIMULATOR
            if([NSProcessInfo.processInfo.arguments containsObject:@"--diagnostic-trap-test"]){
                zone_indirect_failure(Z_EXPORT__indirect_function_table(&h->engine),NULL,UINT32_MAX,"diagnostic self-test");
                wasm_rt_trap(WASM_RT_TRAP_CALL_INDIRECT);
            }
            #endif
            // Load campaign objects on demand instead of prefetching the full
            // model list into the phone's memory before the level starts.
            const char *args[]={"xr_3da","-nosplash","-nointro","-nogameintro","-noprefetch","-fsltx","/opfs/fsgame.ltx"};
            u64 argv=Z_EXPORT_malloc(&h->engine,sizeof args+8);
            for(unsigned i=0;i<sizeof args/sizeof *args;i++) {
                size_t bytes=strlen(args[i])+1;u64 text=Z_EXPORT_malloc(&h->engine,bytes);
                memcpy(z_pointer(h,text,bytes),args[i],bytes);z_write64(h,argv+8*i,text);
            }
            fprintf(stderr,"[native app] Entering engine main; native cores=%ld\n",sysconf(_SC_NPROCESSORS_ONLN));
            z_write64(h,argv+sizeof args,0);h->status=(int)Z_EXPORT_main(&h->engine,sizeof args/sizeof *args,argv);
        }
        if(h->yield_reason==1&&h->main_loop) {
            z_input_focus(h,true);s->mouse_x=s->runtime->width/2;s->mouse_y=s->runtime->height/2;
            z_input_mouse(h,33,0,0,s->mouse_x,s->mouse_y,0,0);
            #if TARGET_OS_SIMULATOR
            if(smoke)fprintf(stderr,"[native app] main loop callback=%llu argument=%llu thread=%llu\n",(unsigned long long)h->main_loop,(unsigned long long)h->main_loop_arg,(unsigned long long)h->pthread);
            #endif
            status(s,ZEngineRunning,"Native engine running");
            while(h->main_loop&&!atomic_load(&s->runtime->failures)) {
                wasm_rt_trap_t trap=wasm_rt_impl_try();
                if(trap){fail(s,wasm_rt_strerror(trap));return NULL;}
                checkpoint(s);double start=Z_IMPORT_emscripten_get_now(h);
                z_pump(h);input_frame(s);z_input_frame_time(h,1000.0/30);
                z_call_void(h,h->main_loop,h->main_loop_arg);
                #if TARGET_OS_SIMULATOR
                if(smoke&&atomic_load(&s->frames)==59)smoke_frame(s);
                #endif
                if(!z_gl_present(h)){fail(s,"The iPhone graphics surface could not present a frame.");return NULL;}
                atomic_store(&s->width,s->runtime->width);atomic_store(&s->height,s->runtime->height);
                atomic_store(&s->cursor,s->runtime->cursor_visible);atomic_fetch_add(&s->frames,1);
                double remaining=1000.0/30-(Z_IMPORT_emscripten_get_now(h)-start);
                if(remaining>0) {struct timespec delay={.tv_nsec=(long)(remaining*1000000)};nanosleep(&delay,NULL);}
            }
        }
        if(atomic_load(&s->runtime->failures)){fail(s,"An engine worker stopped unexpectedly.");return NULL;}
        z_audio_pause(h,true);z_gl_suspend(h);atomic_store(&s->runtime->stopping,true);
        status(s,ZEngineEnded,"Game closed. Relaunch the app to start another session.");
        // Shared workers may still hold native/guest pointers. Keep the heap,
        // imported module and CAEAGLLayer alive for the process; never free or
        // reuse this first session underneath them.
        return NULL;
    }
}
bool ZEngineCanStart(void) { return atomic_load(&current_session)==NULL; }
bool ZEngineStart(void *layer,const char *game,const char *overlay,double width,double height) {
    if(!NSThread.isMainThread||!game||!overlay||!ZEngineCanStart())return false;
    native_log_setup();
    Session *s=calloc(1,sizeof *s);ZRuntime *rt=calloc(1,sizeof *rt);struct w2c_a *h=calloc(1,sizeof *h);
    if(!s||!rt||!h){free(s);free(rt);free(h);return false;}
    s->runtime=rt;s->host=h;h->runtime=rt;rt->threads=h;rt->width=1280;rt->height=720;rt->offline=true;
    pthread_mutex_init(&rt->lock,NULL);pthread_mutex_init(&s->lock,NULL);pthread_cond_init(&s->changed,NULL);
    s->game=strdup(game);s->overlay=strdup(overlay);atomic_store(&s->view_width,fmax(1,width));atomic_store(&s->view_height,fmax(1,height));
    atomic_store(&s->width,1280);atomic_store(&s->height,720);atomic_store(&s->phase,ZEngineStarting);
    snprintf(s->status,sizeof s->status,"Starting the native engine…");
    if(!s->game||!s->overlay||!z_gl_ios_attach(rt,layer)){free(s->game);free(s->overlay);free(s);free(rt);free(h);return false;}
    atomic_store(&current_session,s);wasm_rt_init();
    pthread_attr_t attributes;pthread_attr_init(&attributes);pthread_attr_setstacksize(&attributes,16*1024*1024);
    int error=pthread_create(&s->thread,&attributes,run,s);pthread_attr_destroy(&attributes);
    if(error){status(s,ZEngineFailed,"The native engine thread could not be started.");return false;}
    pthread_detach(s->thread);return true;
}
static void pause_flag(unsigned flag,bool paused) {
    Session *s=atomic_load(&current_session);if(!s)return;
    if(paused)atomic_fetch_or(&s->pause_flags,flag);else atomic_fetch_and(&s->pause_flags,~flag);
    pthread_mutex_lock(&s->lock);pthread_cond_broadcast(&s->changed);
    double deadline=ZHostMonotonicSeconds()+2;
    while(paused&&!s->pause_ack&&atomic_load(&s->phase)<ZEngineEnded) {
        double remaining=deadline-ZHostMonotonicSeconds();if(remaining<=0)break;
        struct timespec timeout={.tv_sec=(time_t)remaining,.tv_nsec=(long)((remaining-floor(remaining))*1000000000)};
        pthread_cond_timedwait_relative_np(&s->changed,&s->lock,&timeout);
    }
    pthread_mutex_unlock(&s->lock);
}
void ZEngineSetPaused(bool paused) { pause_flag(1,paused); }
void ZEngineSetActive(bool active) { pause_flag(2,!active); }
void ZEngineStop(void) {
    Session *s=atomic_load(&current_session);if(!s)return;
    atomic_store(&s->stopped,true);atomic_store(&s->runtime->stopping,true);
    status(s,ZEngineEnded,"Game closed. Relaunch the app to start another session.");
    // Park the owner at its next checkpoint. It must not longjmp out of an
    // atomic wait while that wait's stack record is still registered.
}
void ZEngineSetViewSize(double width,double height) {
    Session *s=atomic_load(&current_session);if(!s||!isfinite(width)||!isfinite(height))return;
    atomic_store(&s->view_width,fmax(1,width));atomic_store(&s->view_height,fmax(1,height));
}
void ZEnginePointer(float x,float y,bool down) {
    Session *s=atomic_load(&current_session);if(!s||!isfinite(x)||!isfinite(y)||atomic_load(&s->phase)!=ZEngineRunning)return;
    Pointer p={fmaxf(0,fminf(1,x)),fmaxf(0,fminf(1,y)),down};
    pthread_mutex_lock(&s->lock);
    if(s->pointer_count==256){s->pointer_count=0;s->reset_pointer=true;}
    s->pointers[s->pointer_count++]=p;pthread_mutex_unlock(&s->lock);
}
ZEngineInfo ZEngineGetInfo(void) {
    Session *s=atomic_load(&current_session);if(!s)return (ZEngineInfo){0};
    int phase=atomic_load(&s->phase);
    if(phase<ZEngineEnded&&atomic_load(&s->pause_flags))phase=ZEnginePaused;
    return (ZEngineInfo){phase,atomic_load(&s->width),atomic_load(&s->height),atomic_load(&s->frames),atomic_load(&s->cursor)};
}
void ZEngineCopyStatus(char *output,size_t capacity) {
    if(!output||!capacity)return;Session *s=atomic_load(&current_session);
    if(!s){snprintf(output,capacity,"Native engine ready");return;}
    pthread_mutex_lock(&s->lock);snprintf(output,capacity,"%s",s->status);pthread_mutex_unlock(&s->lock);
}
#endif
