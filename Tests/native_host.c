#define _POSIX_C_SOURCE 200809L
#include "Host.h"
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#ifdef __APPLE__
#include <OpenAL/al.h>
#else
#include <AL/al.h>
#endif

static u32 word(struct w2c_a *h,u64 p) { u32 v;memcpy(&v,z_pointer(h,p,4),4);return v; }
static void text(struct w2c_a *h,u64 p,const char *s) { memcpy(z_pointer(h,p,strlen(s)+1),s,strlen(s)+1); }
static int get(struct w2c_a *h,u64 scratch,const char *name) {
    text(h,scratch,name);Z_IMPORT__wasmfs_opfs_get_child(h,0,1,scratch,scratch+256,scratch+260);return (int32_t)word(h,scratch+260);
}
typedef struct { struct w2c_a *host;u32 file;u64 buffer; } Reader;
static void *read_parallel(void *pointer) {
    Reader *r=pointer;
    for(int i=0;i<100;i++) {
        assert(Z_IMPORT__wasmfs_opfs_read_access(r->host,r->file,r->buffer,6,0)==6);
        assert(!memcmp(z_pointer(r->host,r->buffer,6),"mobile",6));
    }
    return NULL;
}
int main(void) {
    char base[]="/tmp/zone-host-test-XXXXXX";assert(mkdtemp(base));
    char game[1024],data[1024],file[1100];
    snprintf(game,sizeof game,"%s/game",base);snprintf(data,sizeof data,"%s/data",base);assert(!mkdir(game,0700));assert(!mkdir(data,0700));
    snprintf(file,sizeof file,"%s/test.db",game);int fd=open(file,O_CREAT|O_WRONLY|O_EXCL,0600);assert(fd>=0);assert(write(fd,"original",8)==8);close(fd);
    snprintf(file,sizeof file,"%s/large.db",game);fd=open(file,O_CREAT|O_RDWR|O_EXCL,0600);assert(fd>=0);
    assert(!ftruncate(fd,((off_t)1<<32)+32));assert(pwrite(fd,"WASM64",6,((off_t)1<<32)+16)==6);close(fd);
    snprintf(file,sizeof file,"%s/link",game);assert(!symlink("../outside",file));
    wasm_rt_init();ZRuntime *rt=calloc(1,sizeof *rt);struct w2c_a *h=calloc(1,sizeof *h);assert(rt&&h);
    h->runtime=rt;rt->threads=h;pthread_mutex_init(&rt->lock,NULL);z_current_thread=h;
    rt->files=z_files_open(game,data);assert(rt->files);
    assert(z_memory_open(rt,5120));void *heap=(void *)rt->memory.data;
    assert(Z_IMPORT_emscripten_resize_heap(h,rt->memory.size));
    assert(!Z_IMPORT_emscripten_resize_heap(h,rt->memory.size+65536));
    assert((void *)rt->memory.data==heap);
    assert(wasm_rt_impl_try()==WASM_RT_TRAP_NONE);
    wasm2c_xray_instantiate(&h->engine,h);w2c_xray_fi(&h->engine);
    u64 p=Z_EXPORT_malloc(&h->engine,8192);assert(p);
    assert(get(h,p,"missing.db")==-44);
    int original=get(h,p,"test.db");assert(original>0);
    Z_IMPORT__wasmfs_opfs_open_access(h,0,(u32)original,p+280);u32 access=word(h,p+280);assert((int32_t)access>0);
    assert(Z_IMPORT__wasmfs_opfs_read_access(h,access,p+512,8,0)==8);assert(!memcmp(z_pointer(h,p+512,8),"original",8));
    text(h,p+512,"mobile");assert(Z_IMPORT__wasmfs_opfs_write_access(h,access,p+512,6,0)==6);
    Z_IMPORT__wasmfs_opfs_set_size_access(h,0,access,6,p+288);assert(!word(h,p+288));
    Z_IMPORT__wasmfs_opfs_get_size_file(h,0,(u32)original,p+296);assert(z_read64(h,p+296)==6);
    snprintf(file,sizeof file,"%s/test.db",game);fd=open(file,O_RDONLY);char bytes[9]={0};assert(read(fd,bytes,8)==8);assert(!strcmp(bytes,"original"));close(fd);
    int reopened=get(h,p,"test.db");assert(reopened>0);
    assert(Z_IMPORT__wasmfs_opfs_read_access(h,(u32)reopened,p+512,6,0)==6);assert(!memcmp(z_pointer(h,p+512,6),"mobile",6));
    Reader readers[4];pthread_t workers[4];
    for(int i=0;i<4;i++){readers[i]=(Reader){h,access,p+1024+(u64)i*128};assert(!pthread_create(&workers[i],NULL,read_parallel,&readers[i]));}
    for(int i=0;i<4;i++)assert(!pthread_join(workers[i],NULL));
    int large=get(h,p,"large.db");assert(large>0);Z_IMPORT__wasmfs_opfs_get_size_file(h,0,(u32)large,p+296);assert(z_read64(h,p+296)==((u64)1<<32)+32);
    assert(Z_IMPORT__wasmfs_opfs_read_access(h,(u32)large,p+512,6,((u64)1<<32)+16)==6);assert(!memcmp(z_pointer(h,p+512,6),"WASM64",6));
    u64 high_guest=((u64)1<<32)+4096;
    assert(Z_IMPORT__wasmfs_opfs_read_access(h,(u32)large,high_guest,6,((u64)1<<32)+16)==6);
    assert(!memcmp(z_pointer(h,high_guest,6),"WASM64",6));
    assert(get(h,p,"../outside")<0);assert(get(h,p,"/etc/passwd")<0);assert(get(h,p,"link")<0);assert(get(h,p,"a\\b")<0);
    // A released access handle must not close its still-live file node. Handle
    // IDs are recycled instead of exhausting after repeated open/close cycles.
    for(unsigned i=0;i<70000;i++){Z_IMPORT__wasmfs_opfs_open_access(h,0,(u32)original,p+280);u32 temporary=word(h,p+280);assert((int32_t)temporary>0);Z_IMPORT__wasmfs_opfs_close_access(h,0,temporary,p+288);}
    assert(Z_IMPORT__wasmfs_opfs_read_access(h,access,p+512,6,0)==6);
    puts("Native filesystem: read-only originals, shared copy-on-write handles, 4-GiB offsets, parallel reads, path containment and 70,000 handle cycles passed.");
    u64 device=Z_IMPORT_alcOpenDevice(h,0);
    if(device) {
        u64 context=Z_IMPORT_alcCreateContext(h,device,0);assert(context);assert(Z_IMPORT_alcMakeContextCurrent(h,context));
        Z_IMPORT_alGenBuffers(h,1,p+600);u32 buffer=word(h,p+600);assert(buffer);
        memset(z_pointer(h,p+640,32),0,32);Z_IMPORT_alBufferData(h,buffer,AL_FORMAT_MONO16,p+640,32,8000);
        Z_IMPORT_alGenSources(h,1,p+604);u32 source=word(h,p+604);assert(source);
        Z_IMPORT_alSourceQueueBuffers(h,source,1,p+600);Z_IMPORT_alSourcePlay(h,source);
        Z_IMPORT_alGetSourcei(h,source,AL_BUFFERS_QUEUED,p+608);assert(word(h,p+608)==1);assert(Z_IMPORT_alGetError(h)==AL_NO_ERROR);
        Z_IMPORT_alSourceStop(h,source);Z_IMPORT_alSourceUnqueueBuffers(h,source,1,p+612);assert(word(h,p+612)==buffer);
        Z_IMPORT_alDeleteSources(h,1,p+604);Z_IMPORT_alDeleteBuffers(h,1,p+600);assert(Z_IMPORT_alGetError(h)==AL_NO_ERROR);
        assert(Z_IMPORT_alcMakeContextCurrent(h,0));Z_IMPORT_alcDestroyContext(h,context);assert(Z_IMPORT_alcCloseDevice(h,device));
        puts("Native OpenAL: context, PCM upload, source queue, playback, stop, unqueue and cleanup passed.");
    } else puts("Native OpenAL playback test skipped: this runner has no available output device.");
    Z_EXPORT_free(&h->engine,p);wasm2c_xray_free(&h->engine);z_files_close(rt->files);z_memory_close(rt);free(h);free(rt);wasm_rt_free();
    snprintf(file,sizeof file,"%s/test.db",game);unlink(file);snprintf(file,sizeof file,"%s/large.db",game);unlink(file);snprintf(file,sizeof file,"%s/link",game);unlink(file);snprintf(file,sizeof file,"%s/test.db",data);unlink(file);rmdir(game);rmdir(data);rmdir(base);
    return 0;
}
