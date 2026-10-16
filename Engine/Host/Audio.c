#include "Host.h"
#ifdef __APPLE__
#include <OpenAL/al.h>
#include <OpenAL/alc.h>
#else
#include <AL/al.h>
#include <AL/alc.h>
#endif
#include <stdlib.h>
#include <string.h>

typedef struct ZAudioString { struct ZAudioString *next;size_t bytes;u64 guest;char text[]; } ZAudioString;
typedef struct {
    pthread_mutex_t lock;
    ALCdevice *devices[64];
    ALCcontext *contexts[64];
    ZAudioString *strings;
} ZAudio;
static ZAudio *audio(struct w2c_a *h) {
    pthread_mutex_lock(&h->runtime->lock);
    if(!h->runtime->audio) {
        ZAudio *a=calloc(1,sizeof *a);if(!a){pthread_mutex_unlock(&h->runtime->lock);wasm_rt_trap(WASM_RT_TRAP_EXHAUSTION);}
        pthread_mutex_init(&a->lock,NULL);h->runtime->audio=a;
    }
    ZAudio *a=h->runtime->audio;pthread_mutex_unlock(&h->runtime->lock);return a;
}
static ALCdevice *device(struct w2c_a *h,u64 id) {
    if(!id)return NULL;
    ZAudio *a=audio(h);
    if(id<0x1000||id>=0x1040||!a->devices[id-0x1000])z_missing(h,"invalid native OpenAL device handle");
    return a->devices[id-0x1000];
}
static ALCcontext *context(struct w2c_a *h,u64 id) {
    if(!id)return NULL;
    ZAudio *a=audio(h);
    if(id<0x2000||id>=0x2040||!a->contexts[id-0x2000])z_missing(h,"invalid native OpenAL context handle");
    return a->contexts[id-0x2000];
}
static u64 string_copy(struct w2c_a *h,const char *s,bool list) {
    if(!s)return 0;
    size_t length=0;
    if(list){while(length<65534&&(s[length]||s[length+1]))length++;length+=2;}
    else length=strlen(s)+1;
    ZAudio *a=audio(h);pthread_mutex_lock(&a->lock);
    for(ZAudioString *p=a->strings;p;p=p->next)if(p->bytes==length&&!memcmp(p->text,s,length)){pthread_mutex_unlock(&a->lock);return p->guest;}
    ZAudioString *p=malloc(sizeof *p+length);if(!p){pthread_mutex_unlock(&a->lock);wasm_rt_trap(WASM_RT_TRAP_EXHAUSTION);}
    p->bytes=length;memcpy(p->text,s,length);p->guest=Z_EXPORT_malloc(&h->engine,length);memcpy(z_pointer(h,p->guest,length),s,length);
    p->next=a->strings;a->strings=p;pthread_mutex_unlock(&a->lock);return p->guest;
}
u64 Z_IMPORT_alcOpenDevice(struct w2c_a *h,u64 name) {
    ALCdevice *d=alcOpenDevice(name?z_string(h,name):NULL);if(!d)return 0;
    ZAudio *a=audio(h);pthread_mutex_lock(&a->lock);
    for(unsigned i=0;i<64;i++)if(!a->devices[i]){a->devices[i]=d;pthread_mutex_unlock(&a->lock);return 0x1000+i;}
    pthread_mutex_unlock(&a->lock);alcCloseDevice(d);return 0;
}
u32 Z_IMPORT_alcCloseDevice(struct w2c_a *h,u64 id) {
    ALCdevice *d=device(h,id);if(!d)return ALC_FALSE;ZAudio *a=audio(h);ALCboolean result=alcCloseDevice(d);
    if(result){pthread_mutex_lock(&a->lock);a->devices[id-0x1000]=NULL;pthread_mutex_unlock(&a->lock);}return result;
}
u64 Z_IMPORT_alcCreateContext(struct w2c_a *h,u64 id,u64 attributes) {
    ALCint values[257];unsigned count=0;bool terminated=!attributes;
    if(attributes) {
        while(count<256){ALCint value;memcpy(&value,z_pointer(h,attributes+count*4,4),4);values[count++]=value;if(!value){terminated=true;break;}
            memcpy(&values[count],z_pointer(h,attributes+count*4,4),4);count++;}
        if(!terminated)z_missing(h,"unterminated OpenAL attribute list");
    }
    ALCcontext *c=alcCreateContext(device(h,id),attributes?values:NULL);if(!c)return 0;
    ZAudio *a=audio(h);pthread_mutex_lock(&a->lock);
    for(unsigned i=0;i<64;i++)if(!a->contexts[i]){a->contexts[i]=c;pthread_mutex_unlock(&a->lock);return 0x2000+i;}
    pthread_mutex_unlock(&a->lock);alcDestroyContext(c);return 0;
}
void Z_IMPORT_alcDestroyContext(struct w2c_a *h,u64 id) {
    ALCcontext *c=context(h,id);if(!c)return;alcDestroyContext(c);ZAudio *a=audio(h);
    pthread_mutex_lock(&a->lock);a->contexts[id-0x2000]=NULL;pthread_mutex_unlock(&a->lock);
}
u32 Z_IMPORT_alcMakeContextCurrent(struct w2c_a *h,u64 id) { return alcMakeContextCurrent(context(h,id)); }
u32 Z_IMPORT_alcGetError(struct w2c_a *h,u64 id) { return alcGetError(device(h,id)); }
u32 Z_IMPORT_alcIsExtensionPresent(struct w2c_a *h,u64 id,u64 name) { return alcIsExtensionPresent(device(h,id),z_string(h,name)); }
u64 Z_IMPORT_alcGetString(struct w2c_a *h,u64 id,u32 param) {
    return string_copy(h,alcGetString(device(h,id),param),!id&&(param==ALC_DEVICE_SPECIFIER||param==0x1013));
}
void Z_IMPORT_alcGetIntegerv(struct w2c_a *h,u64 id,u32 param,u32 count,u64 out) { alcGetIntegerv(device(h,id),param,(ALCsizei)count,z_pointer(h,out,(u64)count*4)); }
u32 Z_IMPORT_alGetError(struct w2c_a *h) { (void)h;return alGetError(); }
u64 Z_IMPORT_alGetString(struct w2c_a *h,u32 param) { return string_copy(h,alGetString(param),false); }
u32 Z_IMPORT_alIsExtensionPresent(struct w2c_a *h,u64 name) { return alIsExtensionPresent(z_string(h,name)); }
u32 Z_IMPORT_alIsSource(struct w2c_a *h,u32 source) { (void)h;return alIsSource(source); }
void Z_IMPORT_alGenSources(struct w2c_a *h,u32 count,u64 out) { alGenSources((ALsizei)count,z_pointer(h,out,(u64)count*4)); }
void Z_IMPORT_alGenBuffers(struct w2c_a *h,u32 count,u64 out) { alGenBuffers((ALsizei)count,z_pointer(h,out,(u64)count*4)); }
void Z_IMPORT_alDeleteSources(struct w2c_a *h,u32 count,u64 at) { alDeleteSources((ALsizei)count,z_pointer(h,at,(u64)count*4)); }
void Z_IMPORT_alDeleteBuffers(struct w2c_a *h,u32 count,u64 at) { alDeleteBuffers((ALsizei)count,z_pointer(h,at,(u64)count*4)); }
void Z_IMPORT_alSourcef(struct w2c_a *h,u32 source,u32 param,f32 value) { (void)h;alSourcef(source,param,value); }
void Z_IMPORT_alSourcei(struct w2c_a *h,u32 source,u32 param,u32 value) { (void)h;alSourcei(source,param,(ALint)value); }
void Z_IMPORT_alSource3f(struct w2c_a *h,u32 source,u32 param,f32 x,f32 y,f32 z) { (void)h;alSource3f(source,param,x,y,z); }
void Z_IMPORT_alSourcePlay(struct w2c_a *h,u32 source) { (void)h;alSourcePlay(source); }
void Z_IMPORT_alSourceStop(struct w2c_a *h,u32 source) { (void)h;alSourceStop(source); }
void Z_IMPORT_alGetSourcei(struct w2c_a *h,u32 source,u32 param,u64 out) { alGetSourcei(source,param,z_pointer(h,out,4)); }
void Z_IMPORT_alBufferData(struct w2c_a *h,u32 buffer,u32 format,u64 data,u32 size,u32 frequency) { alBufferData(buffer,format,z_pointer(h,data,size),(ALsizei)size,(ALsizei)frequency); }
void Z_IMPORT_alSourceQueueBuffers(struct w2c_a *h,u32 source,u32 count,u64 at) { alSourceQueueBuffers(source,(ALsizei)count,z_pointer(h,at,(u64)count*4)); }
void Z_IMPORT_alSourceUnqueueBuffers(struct w2c_a *h,u32 source,u32 count,u64 out) { alSourceUnqueueBuffers(source,(ALsizei)count,z_pointer(h,out,(u64)count*4)); }
void Z_IMPORT_alListener3f(struct w2c_a *h,u32 param,f32 x,f32 y,f32 z) { (void)h;alListener3f(param,x,y,z); }
void Z_IMPORT_alListenerf(struct w2c_a *h,u32 param,f32 value) { (void)h;alListenerf(param,value); }
void Z_IMPORT_alListenerfv(struct w2c_a *h,u32 param,u64 values) { alListenerfv(param,z_pointer(h,values,param==AL_ORIENTATION?24:(param==AL_POSITION||param==AL_VELOCITY?12:4))); }
