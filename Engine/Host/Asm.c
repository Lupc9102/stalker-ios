#include "Host.h"
#include <stdio.h>
#include <string.h>

// These are the reviewed EM_ASM sites in the pinned engine. They are translated
// to native services; unknown code addresses always trap rather than executing JS.
u32 z_asm(struct w2c_a *h,u64 code,const long double *args,unsigned count) {
    u64 a=count?(u64)args[0]:0,b=count>1?(u64)args[1]:0;
    switch(code) {
    case 5915112:
        fprintf(stderr,"[engine] %s\n%s\n",z_string(h,a),z_string(h,b));return 0;
    case 5916119:
        fprintf(stderr,"[engine] Fatal dialog: %s\n",z_string(h,a));
        return 'a'; // Choose Abort; never silently ignore a real engine assertion.
    case 5915169:
        z_pointer(h,a,4);h->runtime->frame_time_pointer=a;return 0;
    case 5915559:
        z_pointer(h,a,8);h->runtime->mouse_pointer=a;h->runtime->mouse_scale=count>1?(double)args[1]:1;return 0;
    case 5916334:case 5916481:
        return 0; // Browser audio/capture unavailable in this headless boot host.
    default:fprintf(stderr,"[engine] EM_ASM address: %llu\n",(unsigned long long)code);z_missing(h,"unported EM_ASM code address");
    }
}
static u32 read_call(struct w2c_a *h,u64 code,u64 signature,u64 packet) {
    const char *sig=z_string(h,signature);long double args[16]={0};unsigned count=(unsigned)strlen(sig);
    if(count>16)z_missing(h,"EM_ASM with more than sixteen arguments");
    for(unsigned i=0;sig[i];i++) {
        if(sig[i]!='i')packet=(packet+7)&~(u64)7;
        if(sig[i]=='p')args[i]=z_read64(h,packet);
        else if(sig[i]=='j')args[i]=(int64_t)z_read64(h,packet);
        else if(sig[i]=='i'){int32_t v;memcpy(&v,z_pointer(h,packet,4),4);args[i]=v;}
        else if(sig[i]=='d'){double v;memcpy(&v,z_pointer(h,packet,8),8);args[i]=v;}
        else {fprintf(stderr,"[engine] EM_ASM signature: %s, code %llu\n",sig,(unsigned long long)code);z_missing(h,"EM_ASM argument type");}
        packet+=sig[i]=='i'?4:8;
    }
    return z_asm(h,code,args,count);
}
u32 Z_IMPORT_emscripten_asm_const_int(struct w2c_a *h,u64 code,u64 sig,u64 args) { return read_call(h,code,sig,args); }
u32 Z_IMPORT_emscripten_asm_const_int_sync_on_main_thread(struct w2c_a *h,u64 code,u64 sig,u64 args) { return read_call(h,code,sig,args); }
u64 Z_IMPORT_emscripten_asm_const_ptr_sync_on_main_thread(struct w2c_a *h,u64 code,u64 sig,u64 args) { return read_call(h,code,sig,args); }
