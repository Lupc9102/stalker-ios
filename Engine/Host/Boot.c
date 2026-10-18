#define _POSIX_C_SOURCE 200809L
#include "Host.h"
#include "Input.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#if defined(ZONE_NATIVE_GLES)
#include "Graphics.h"
static bool save_frame(struct w2c_a *h,const char *path) {
    u32 width=h->runtime->width,height=h->runtime->height;
    if(!width||!height||width>4096||height>4096)return false;
    size_t size=(size_t)width*height*4;unsigned char *pixels=malloc(size);if(!pixels)return false;
    glBindFramebuffer(GL_READ_FRAMEBUFFER,z_gl_framebuffer(h,0));glBindBuffer(GL_PIXEL_PACK_BUFFER,0);
    glPixelStorei(GL_PACK_ALIGNMENT,1);glPixelStorei(GL_PACK_ROW_LENGTH,0);
    glPixelStorei(GL_PACK_SKIP_ROWS,0);glPixelStorei(GL_PACK_SKIP_PIXELS,0);
    glReadPixels(0,0,width,height,GL_RGBA,GL_UNSIGNED_BYTE,pixels);
    if(glGetError()!=GL_NO_ERROR){free(pixels);return false;}
    FILE *file=fopen(path,"wb");if(!file){free(pixels);return false;}
    bool success=fprintf(file,"P6\n%u %u\n255\n",width,height)>0;
    for(u32 y=height;y>0&&success;y--)for(u32 x=0;x<width;x++) {
        if(fwrite(pixels+((size_t)(y-1)*width+x)*4,1,3,file)!=3){success=false;break;}
    }
    if(fclose(file))success=false;free(pixels);return success;
}
#endif

// This executable deliberately runs the real constructors and main, unlike the
// module-only CPU probe. Unsupported imports remain fatal and named in its log.
int main(int argc,char **argv) {
    wasm_rt_init();
    ZRuntime *runtime=calloc(1,sizeof *runtime);
    struct w2c_a *h=calloc(1,sizeof *h);
    if(!runtime||!h)return 1;
    h->runtime=runtime;runtime->threads=h;runtime->width=960;runtime->height=540;
    const char *offline=getenv("ZONE_OFFLINE");runtime->offline=offline&&!strcmp(offline,"1");
    pthread_mutex_init(&runtime->lock,NULL);z_current_thread=h;
    char temporary[]="/tmp/zone-engine-XXXXXX";
    const char *overlay=argc>2?argv[2]:mkdtemp(temporary);
    if(!overlay){perror("Temporary app-data folder");return 1;}
    runtime->files=z_files_open(argc>1?argv[1]:".",overlay);
    if(!runtime->files)return 1;
#if defined(ZONE_NATIVE_GLES) && !defined(__APPLE__)
    if(!z_gl_egl_attach(runtime))return 1;
#endif
    fprintf(stderr,"[engine] Allocating imported memory64; no JIT\n");
    const char *heap_setting=getenv("ZONE_HEAP_MB");
    u32 heap_mb=heap_setting?(u32)strtoul(heap_setting,NULL,10):2048;
    if(!z_memory_open(runtime,heap_mb))return 1;
    if(setjmp(h->yielded)==0) {
        wasm_rt_trap_t trap=wasm_rt_impl_try();
        if(trap) { fprintf(stderr,"[engine] Native boot trapped: %s\n",wasm_rt_strerror(trap));return 78; }
        wasm2c_xray_instantiate(&h->engine,h);
        fprintf(stderr,"[engine] Running static constructors\n");
        w2c_xray_fi(&h->engine);
        // Prefetching the full object/model list raises the mobile memory peak.
        // Let campaign assets load when the engine requests them instead.
        const char *args[9]={"xr_3da","-nosplash","-nointro","-nogameintro","-noprefetch","-fsltx","/opfs/fsgame.ltx"};
        unsigned count=7;
        const char *campaign=getenv("ZONE_START_NEW_GAME");
        if(campaign&&!strcmp(campaign,"1")) {
            args[count++]="-start";
            args[count++]="server(all/single/alife/new) client(localhost)";
        }
        u64 pointers=Z_EXPORT_malloc(&h->engine,(count+1)*8);
        for(unsigned i=0;i<count;i++) {
            size_t size=strlen(args[i])+1;u64 p=Z_EXPORT_malloc(&h->engine,size);
            memcpy(z_pointer(h,p,size),args[i],size);z_write64(h,pointers+8*i,p);
        }
        z_write64(h,pointers+count*8,0);
        fprintf(stderr,"[engine] ENTERING REAL ENGINE MAIN\n");
        h->status=(int)Z_EXPORT_main(&h->engine,count,pointers);
        fprintf(stderr,"[engine] main returned %d\n",h->status);
    } else fprintf(stderr,"[engine] Main yielded: reason %d, status %d\n",h->yield_reason,h->status);
#if defined(ZONE_NATIVE_GLES)
    if(!atomic_load(&runtime->failures)&&h->yield_reason==1&&h->main_loop) {
        unsigned limit=argc>3?(unsigned)strtoul(argv[3],NULL,10):1;
        const char *input_test=getenv("ZONE_MENU_INPUT");
        bool options=input_test&&!strcmp(input_test,"options");
        bool pointer_options=input_test&&!strcmp(input_test,"pointer-options");
        if((options||pointer_options)&&limit<70)limit=70;
        if(limit>3600)limit=3600;
        z_input_focus(h,true);
        z_input_mouse(h,33,0,0,runtime->width/2,runtime->height/2,0,0);
        fprintf(stderr,"[engine] Running up to %u real engine frames\n",limit);
        for(unsigned frame=0;frame<limit&&h->main_loop;frame++) {
            wasm_rt_trap_t trap=wasm_rt_impl_try();
            if(trap){
                fprintf(stderr,"[engine] Frame trapped: %s\n",wasm_rt_strerror(trap));
                if(argc>4&&save_frame(h,argv[4]))
                    fprintf(stderr,"[engine] Captured last framebuffer after failure; campaign not verified: %s\n",argv[4]);
                return 78;
            }
            z_input_frame_time(h,1000.0/60);
            if(options&&frame>=40&&frame<=47) {
                u32 key=frame>=46?13:40;const char *name=frame>=46?"Enter":"ArrowDown";
                bool down=frame%2==0,accepted=z_input_key(h,key,name,name,0,down,0);
                fprintf(stderr,"[engine] Native input test: %s %s; handled=%d callback=%llu owner=%llu thread=%llu\n",name,down?"down":"up",accepted,
                  (unsigned long long)h->runtime->events[down?2:3].callback,(unsigned long long)h->runtime->events[down?2:3].owner,(unsigned long long)h->pthread);
            }
            if(pointer_options&&(frame==40||frame==62||frame==63)) {
                int32_t x=(int32_t)(runtime->width*0.178),y=(int32_t)(runtime->height*0.592);
                bool handled=z_input_mouse(h,frame==40?8:(frame==62?5:6),0,frame==62?1:0,x,y,
                  frame==40?x-(int32_t)runtime->width/2:0,frame==40?y-(int32_t)runtime->height/2:0);
                fprintf(stderr,"[engine] Native pointer test: %s; handled=%d at %d,%d\n",frame==40?"move":(frame==62?"down":"up"),handled,x,y);
            }
            z_pump(h);z_call_void(h,h->main_loop,h->main_loop_arg);
            if(!z_gl_present(h)) { fprintf(stderr,"[engine] Present failed\n");return 78; }
            fprintf(stderr,"[engine] Rendered engine frame %u\n",frame+1);
            struct timespec interval={.tv_nsec=17000000};nanosleep(&interval,NULL);
        }
        if(argc>4) {
            if(!save_frame(h,argv[4])){fprintf(stderr,"[engine] Frame capture failed\n");return 78;}
            fprintf(stderr,"[engine] Captured actual engine framebuffer: %s\n",argv[4]);
        }
    }
#endif
    // This process owns the workers. Returning exits them; app integration must
    // implement cooperative engine shutdown before reclaiming their memory.
    return atomic_load(&runtime->failures)?78:h->status;
}
