#include "Graphics.h"
#include "BC.h"
#include <stdlib.h>

// ES on iPhone need not accept PC DDS block formats. Decode each incoming mip
// into a temporary RGBA upload; retain only the actual GL texture afterwards.
static unsigned char *decode(struct w2c_a *h,u32 format,u32 width,u32 height,u32 depth,u32 bytes,u64 data) {
    size_t compressed,rgba;
    if(!z_bc_sizes(format,width,height,depth,&compressed,&rgba)||compressed!=bytes||rgba>h->runtime->memory.size)
        z_missing(h,"invalid BC texture dimensions or compressed byte count");
    unsigned char *pixels=malloc(rgba);if(!pixels)wasm_rt_trap(WASM_RT_TRAP_EXHAUSTION);
    GLint buffer=0;glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING,&buffer);
    const void *source;
    if(buffer) {
        GLint64 size=0;glGetBufferParameteri64v(GL_PIXEL_UNPACK_BUFFER,GL_BUFFER_SIZE,&size);
        if(size<0||data>(u64)size||bytes>(u64)size-data) { free(pixels);wasm_rt_trap(WASM_RT_TRAP_OOB); }
        source=glMapBufferRange(GL_PIXEL_UNPACK_BUFFER,(GLintptr)data,bytes,GL_MAP_READ_BIT);
        if(!source) { free(pixels);z_missing(h,"BC texture unpack buffer could not be mapped"); }
    } else source=z_pointer(h,data,bytes);
    bool valid=z_bc_decode(format,width,height,depth,source,bytes,pixels,rgba);
    if(buffer&&!glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER))valid=false;
    if(!valid) { free(pixels);z_missing(h,"BC texture decode failed"); }
    return pixels;
}
static const GLenum unpack_names[]={GL_UNPACK_ALIGNMENT,GL_UNPACK_ROW_LENGTH,GL_UNPACK_IMAGE_HEIGHT,
    GL_UNPACK_SKIP_PIXELS,GL_UNPACK_SKIP_ROWS,GL_UNPACK_SKIP_IMAGES};
typedef struct { GLint buffer,values[6]; } Unpack;
static Unpack begin_upload(void) {
    Unpack saved;glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING,&saved.buffer);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER,0);
    for(unsigned i=0;i<6;i++){glGetIntegerv(unpack_names[i],saved.values+i);glPixelStorei(unpack_names[i],i?0:1);}
    return saved;
}
static void end_upload(Unpack saved) {
    for(unsigned i=0;i<6;i++)glPixelStorei(unpack_names[i],saved.values[i]);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER,saved.buffer);
}
void z_gl_compressed_image(struct w2c_a *h,u32 dimensions,u32 target,u32 level,u32 format,
                          u32 width,u32 height,u32 depth,u32 border,u32 bytes,u64 data) {
    GLint buffer=0;if(!data)glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING,&buffer);
    bool empty=!data&&!buffer;
    if(!z_gl_bc_needs_decode(h,format)) {
        const void *source=empty?NULL:z_gl_pixel_bytes(h,data,bytes,false);
        if(dimensions==2)glCompressedTexImage2D(target,level,format,width,height,border,bytes,source);
        else glCompressedTexImage3D(target,level,format,width,height,depth,border,bytes,source);
        return;
    }
    size_t compressed,rgba;
    if(empty&&(!z_bc_sizes(format,width,height,depth,&compressed,&rgba)||compressed!=bytes))
        z_missing(h,"invalid empty BC texture allocation");
    unsigned char *pixels=empty?NULL:decode(h,format,width,height,depth,bytes,data);Unpack saved=begin_upload();
    if(dimensions==2)glTexImage2D(target,level,z_gl_texture_format(h,format),width,height,border,GL_RGBA,GL_UNSIGNED_BYTE,pixels);
    else glTexImage3D(target,level,z_gl_texture_format(h,format),width,height,depth,border,GL_RGBA,GL_UNSIGNED_BYTE,pixels);
    end_upload(saved);free(pixels);
}
void z_gl_compressed_sub_image(struct w2c_a *h,u32 dimensions,u32 target,u32 level,u32 x,u32 y,u32 z,
                              u32 width,u32 height,u32 depth,u32 format,u32 bytes,u64 data) {
    if(!z_gl_bc_needs_decode(h,format)) {
        const void *source=z_gl_pixel_bytes(h,data,bytes,false);
        if(dimensions==2)glCompressedTexSubImage2D(target,level,x,y,width,height,format,bytes,source);
        else glCompressedTexSubImage3D(target,level,x,y,z,width,height,depth,format,bytes,source);
        return;
    }
    unsigned char *pixels=decode(h,format,width,height,depth,bytes,data);Unpack saved=begin_upload();
    if(dimensions==2)glTexSubImage2D(target,level,x,y,width,height,GL_RGBA,GL_UNSIGNED_BYTE,pixels);
    else glTexSubImage3D(target,level,x,y,z,width,height,depth,GL_RGBA,GL_UNSIGNED_BYTE,pixels);
    end_upload(saved);free(pixels);
}
