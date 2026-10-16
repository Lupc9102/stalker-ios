#define _POSIX_C_SOURCE 200809L
#include "Host.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#if defined(ZONE_NATIVE_GLES)
#include "Graphics.h"
#endif

// This executable deliberately runs the real constructors and main, unlike the
// module-only CPU probe. Unsupported imports remain fatal and named in its log.
int main(int argc,char **argv) {
    wasm_rt_init();
    ZRuntime *runtime=calloc(1,sizeof *runtime);
    struct w2c_a *h=calloc(1,sizeof *h);
    if(!runtime||!h)return 1;
    h->runtime=runtime;runtime->threads=h;runtime->width=960;runtime->height=540;
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
    wasm_rt_allocate_memory_shared(&runtime->memory,32768,262144,true,WASM_DEFAULT_PAGE_SIZE);
    if(setjmp(h->yielded)==0) {
        wasm_rt_trap_t trap=wasm_rt_impl_try();
        if(trap) { fprintf(stderr,"[engine] Native boot trapped: %s\n",wasm_rt_strerror(trap));return 78; }
        wasm2c_xray_instantiate(&h->engine,h);
        fprintf(stderr,"[engine] Running static constructors\n");
        w2c_xray_fi(&h->engine);
        const char *args[]={"xr_3da","-nosplash","-nointro","-nogameintro","-fsltx","/opfs/fsgame.ltx"};
        u64 pointers=Z_EXPORT_malloc(&h->engine,sizeof args+8);
        for(unsigned i=0;i<sizeof args/sizeof *args;i++) {
            size_t size=strlen(args[i])+1;u64 p=Z_EXPORT_malloc(&h->engine,size);
            memcpy(z_pointer(h,p,size),args[i],size);z_write64(h,pointers+8*i,p);
        }
        z_write64(h,pointers+sizeof args,0);
        fprintf(stderr,"[engine] ENTERING REAL ENGINE MAIN\n");
        h->status=(int)Z_EXPORT_main(&h->engine,sizeof args/sizeof *args,pointers);
        fprintf(stderr,"[engine] main returned %d\n",h->status);
    } else fprintf(stderr,"[engine] Main yielded: reason %d, status %d\n",h->yield_reason,h->status);
#if defined(ZONE_NATIVE_GLES)
    if(!atomic_load(&runtime->failures)&&h->yield_reason==1&&h->main_loop) {
        unsigned limit=argc>3?(unsigned)strtoul(argv[3],NULL,10):1;
        if(limit>3600)limit=3600;
        fprintf(stderr,"[engine] Running up to %u real engine frames\n",limit);
        for(unsigned frame=0;frame<limit&&h->main_loop;frame++) {
            wasm_rt_trap_t trap=wasm_rt_impl_try();
            if(trap){fprintf(stderr,"[engine] Frame trapped: %s\n",wasm_rt_strerror(trap));return 78;}
            z_pump(h);z_call_void(h,h->main_loop,h->main_loop_arg);
            if(!z_gl_present(h)) { fprintf(stderr,"[engine] Present failed\n");return 78; }
            fprintf(stderr,"[engine] Rendered engine frame %u\n",frame+1);
        }
    }
#endif
    // This process owns the workers. Returning exits them; app integration must
    // implement cooperative engine shutdown before reclaiming their memory.
    return atomic_load(&runtime->failures)?78:h->status;
}
