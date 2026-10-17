#include "Graphics.h"
#include "BC.h"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct ZGLString { GLenum name; u32 index; u64 guest; struct ZGLString *next; } ZGLString;
typedef struct {
    ZGraphicsProvider provider;
    bool created, current;
    pthread_t owner;
    ZGLString *strings;
    GLsync syncs[1024];
    char *extensions[128];
    unsigned extension_count;
    char *extension_string;
    bool bc_native,bc_srgb_native,force_bc_decode;
} ZGraphics;

static ZGraphics *graphics(struct w2c_a *h) {
    ZGraphics *g=h->runtime->graphics;
    if(!g)z_missing(h,"native graphics provider not attached");
    return g;
}
bool z_gl_attach(ZRuntime *runtime,ZGraphicsProvider provider) {
    if(runtime->graphics||!provider.create||!provider.current||!provider.destroy||!provider.present)return false;
    ZGraphics *g=calloc(1,sizeof *g);if(!g)return false;
    g->provider=provider;runtime->graphics=g;return true;
}
void z_gl_require(struct w2c_a *h) {
    ZGraphics *g=graphics(h);
    if(!g->created||!g->current||!pthread_equal(g->owner,pthread_self())) {
        fprintf(stderr,"[engine] GLES context created=%d current=%d owner=%llu caller=%llu guest=%llu\n",
          g->created,g->current,(unsigned long long)g->owner,(unsigned long long)pthread_self(),(unsigned long long)h->pthread);
        z_missing(h,"GLES call without current context on this native thread");
    }
}
u64 z_gl_count(struct w2c_a *h,u64 count,u64 size) {
    if(count>INT32_MAX||!size||count>h->runtime->memory.size/size)wasm_rt_trap(WASM_RT_TRAP_OOB);
    return count*size;
}
void *z_gl_optional(struct w2c_a *h,u64 address,u64 size) { return address?z_pointer(h,address,size):NULL; }
const GLchar **z_gl_strings(struct w2c_a *h,u64 address,u64 lengths,u32 count) {
    z_pointer(h,address,z_gl_count(h,count,8));
    if(lengths)z_pointer(h,lengths,z_gl_count(h,count,4));
    if(count>65536)wasm_rt_trap(WASM_RT_TRAP_EXHAUSTION);
    const GLchar **strings=calloc(count?count:1,sizeof *strings);
    if(!strings)wasm_rt_trap(WASM_RT_TRAP_EXHAUSTION);
    for(u32 i=0;i<count;i++) {
        u64 p=z_read64(h,address+8*i);GLint n=-1;
        if(lengths)memcpy(&n,z_pointer(h,lengths+4*i,4),4);
        strings[i]=n<0?z_string(h,p):z_pointer(h,p,(u32)n);
    }
    return strings;
}
const void *z_gl_buffer_offset(struct w2c_a *h,GLenum binding,u64 address) {
    GLint buffer=0;glGetIntegerv(binding,&buffer);
    // ES 3 disallows client vertex/index arrays. A guest address is never a
    // native pointer; this path accepts only GPU-buffer offsets.
    if(!buffer||address>INTPTR_MAX)z_missing(h,"GLES vertex/index input requires a bound buffer");
    return (const void *)(uintptr_t)address;
}
void *z_gl_pixel_bytes(struct w2c_a *h,u64 address,u32 bytes,bool pack) {
    GLint buffer=0;glGetIntegerv(pack?GL_PIXEL_PACK_BUFFER_BINDING:GL_PIXEL_UNPACK_BUFFER_BINDING,&buffer);
    if(buffer) { if(address>INTPTR_MAX)wasm_rt_trap(WASM_RT_TRAP_OOB);return (void *)(uintptr_t)address; }
    return z_pointer(h,address,z_gl_count(h,bytes,1));
}
static u32 pixel_size(struct w2c_a *h,GLenum format,GLenum type) {
    switch(type) {
    case GL_UNSIGNED_SHORT_4_4_4_4:case GL_UNSIGNED_SHORT_5_5_5_1:case GL_UNSIGNED_SHORT_5_6_5:return 2;
    case GL_UNSIGNED_INT_2_10_10_10_REV:case GL_UNSIGNED_INT_10F_11F_11F_REV:
    case GL_UNSIGNED_INT_5_9_9_9_REV:case GL_UNSIGNED_INT_24_8:return 4;
    case GL_FLOAT_32_UNSIGNED_INT_24_8_REV:return 8;
    default:break;
    }
    u32 channels=0,bytes=0;
    switch(format) {
    case GL_RED:case GL_RED_INTEGER:case GL_DEPTH_COMPONENT:case GL_ALPHA:case GL_LUMINANCE:channels=1;break;
    case GL_RG:case GL_RG_INTEGER:case GL_LUMINANCE_ALPHA:channels=2;break;
    case GL_RGB:case GL_RGB_INTEGER:channels=3;break;
    case GL_RGBA:case GL_RGBA_INTEGER:channels=4;break;
    default:z_missing(h,"unreviewed GLES pixel format");
    }
    switch(type) {
    case GL_UNSIGNED_BYTE:case GL_BYTE:bytes=1;break;
    case GL_UNSIGNED_SHORT:case GL_SHORT:case GL_HALF_FLOAT:bytes=2;break;
    case GL_UNSIGNED_INT:case GL_INT:case GL_FLOAT:bytes=4;break;
    default:z_missing(h,"unreviewed GLES pixel type");
    }
    return channels*bytes;
}
void *z_gl_pixels(struct w2c_a *h,u64 address,u32 width,u32 height,u32 depth,GLenum format,GLenum type,bool pack,bool allow_null) {
    GLint buffer=0;glGetIntegerv(pack?GL_PIXEL_PACK_BUFFER_BINDING:GL_PIXEL_UNPACK_BUFFER_BINDING,&buffer);
    if(buffer) { if(address>INTPTR_MAX)wasm_rt_trap(WASM_RT_TRAP_OOB);return (void *)(uintptr_t)address; }
    if(!address&&allow_null)return NULL;
    if(width>INT32_MAX||height>INT32_MAX||depth>INT32_MAX)wasm_rt_trap(WASM_RT_TRAP_OOB);
    if(!width||!height||!depth)return z_pointer(h,address,0);
    GLint align=4,row=0,image=0,skip_rows=0,skip_pixels=0,skip_images=0;
    glGetIntegerv(pack?GL_PACK_ALIGNMENT:GL_UNPACK_ALIGNMENT,&align);
    glGetIntegerv(pack?GL_PACK_ROW_LENGTH:GL_UNPACK_ROW_LENGTH,&row);
    glGetIntegerv(pack?GL_PACK_SKIP_ROWS:GL_UNPACK_SKIP_ROWS,&skip_rows);
    glGetIntegerv(pack?GL_PACK_SKIP_PIXELS:GL_UNPACK_SKIP_PIXELS,&skip_pixels);
    if(!pack&&depth>1) {
        glGetIntegerv(GL_UNPACK_IMAGE_HEIGHT,&image);glGetIntegerv(GL_UNPACK_SKIP_IMAGES,&skip_images);
    }
    if(align<=0||align>8||row<0||image<0||skip_rows<0||skip_pixels<0||skip_images<0)wasm_rt_trap(WASM_RT_TRAP_OOB);
    u64 pixel=pixel_size(h,format,type);
    u64 pitch=(z_gl_count(h,row?(u32)row:width,pixel)+align-1)&~((u64)align-1);
    u64 image_pitch=z_gl_count(h,image?(u32)image:height,pitch?pitch:1);
    u64 bytes=z_gl_count(h,(u64)skip_images+depth-1,image_pitch?image_pitch:1)+
              z_gl_count(h,(u64)skip_rows+height-1,pitch?pitch:1)+z_gl_count(h,(u64)skip_pixels+width,pixel);
    return z_pointer(h,address,bytes);
}

static bool extension_available(const char *all,const char *extension) {
    const char *p=all;size_t n=strlen(extension);
    while(p&&(p=strstr(p,extension))) { if((p==all||p[-1]==' ')&&(p[n]==' '||!p[n]))return true;p+=n; }
    return false;
}
static void discover_extensions(ZGraphics *g) {
    // Expose only extensions whose calls/formats are handled by this backend.
    // Timer-query, base-vertex and browser-only extensions remain unavailable.
    static const char *reviewed[]={"GL_EXT_color_buffer_float","GL_EXT_color_buffer_half_float",
      "GL_EXT_texture_filter_anisotropic","GL_OES_texture_float_linear","GL_OES_texture_half_float_linear",
      "GL_OES_vertex_array_object","GL_EXT_draw_buffers","GL_ANGLE_instanced_arrays",
      "GL_KHR_texture_compression_astc_ldr","GL_EXT_texture_compression_s3tc",
      "GL_EXT_texture_compression_dxt1","GL_EXT_texture_compression_s3tc_srgb",
      "GL_EXT_texture_format_BGRA8888","GL_APPLE_texture_format_BGRA8888"};
    const char *all=(const char *)glGetString(GL_EXTENSIONS);if(!all)all="";
    g->bc_native=extension_available(all,"GL_EXT_texture_compression_s3tc");
    g->bc_srgb_native=extension_available(all,"GL_EXT_texture_compression_s3tc_srgb");
    const char *force=getenv("ZONE_FORCE_BC_DECODE");g->force_bc_decode=force&&!strcmp(force,"1");
    size_t bytes=1;
    for(unsigned i=0;i<sizeof reviewed/sizeof *reviewed;i++)if(extension_available(all,reviewed[i])) {
        g->extensions[g->extension_count++]=strdup(reviewed[i]);bytes+=strlen(reviewed[i])+1;
    }
    g->extension_string=calloc(bytes,1);if(!g->extension_string)return;
    for(unsigned i=0;i<g->extension_count;i++) { if(i)strcat(g->extension_string," ");strcat(g->extension_string,g->extensions[i]); }
}
bool z_gl_bc_needs_decode(struct w2c_a *h,GLenum format) {
    ZGraphics *g=graphics(h);
    return z_bc_kind(format)&&(g->force_bc_decode||!(z_bc_srgb(format)?g->bc_srgb_native:g->bc_native));
}
GLenum z_gl_texture_format(struct w2c_a *h,GLenum format) {
    return z_gl_bc_needs_decode(h,format)?(z_bc_srgb(format)?GL_SRGB8_ALPHA8:GL_RGBA8):format;
}
u64 Z_IMPORT_emscripten_webgl_create_context(struct w2c_a *h,u64 target,u64 attributes) {
    (void)target;ZGraphics *g=graphics(h);if(g->created)return 0;
    const unsigned char *a=z_pointer(h,attributes,34);u32 major;memcpy(&major,a+16,4);
    if(major!=2)return 0; // The pinned engine requests WebGL 2 / GLES 3.
    if(!g->provider.create(g->provider.user,h->runtime->width,h->runtime->height))return 0;
    g->created=true;
    if(!g->provider.current(g->provider.user,true))return 0;
    g->current=true;g->owner=pthread_self();discover_extensions(g);
    fprintf(stderr,"[engine] Native GLES: %s / %s\n",glGetString(GL_RENDERER),glGetString(GL_VERSION));
    return 1;
}
u32 Z_IMPORT_emscripten_webgl_make_context_current(struct w2c_a *h,u64 context) {
    ZGraphics *g=graphics(h);if(context>1||(!g->created&&context))return (u32)-5;
    fprintf(stderr,"[engine] GLES make-current %llu guest=%llu native=%llu\n",(unsigned long long)context,(unsigned long long)h->pthread,(unsigned long long)pthread_self());
    if(!g->provider.current(g->provider.user,context!=0))return (u32)-5;
    g->current=context!=0;if(context)g->owner=pthread_self();return 0;
}
u64 Z_IMPORT_emscripten_webgl_get_current_context(struct w2c_a *h) {
    ZGraphics *g=graphics(h);return g->current&&pthread_equal(g->owner,pthread_self())?1:0;
}
u32 Z_IMPORT_emscripten_webgl_enable_extension(struct w2c_a *h,u64 context,u64 extension) {
    if(context!=1)return 0;
    z_gl_require(h);ZGraphics *g=graphics(h);const char *name=z_string(h,extension);
    if(!strncmp(name,"GL_",3))name+=3;
    for(unsigned i=0;i<g->extension_count;i++)if(!strcmp(name,g->extensions[i]+3))return 1;
    return 0;
}
u32 Z_IMPORT_emscripten_webgl_destroy_context(struct w2c_a *h,u64 context) {
    if(context!=1)return (u32)-5;
    z_gl_close(h->runtime);return 0;
}
bool z_gl_present(struct w2c_a *h) { z_gl_require(h);ZGraphics *g=graphics(h);return g->provider.present(g->provider.user); }
bool z_gl_resize(struct w2c_a *h,u32 width,u32 height) {
    ZGraphics *g=h->runtime->graphics;if(!g||!g->created)return true;
    z_gl_require(h);return g->provider.resize&&g->provider.resize(g->provider.user,width,height);
}
void z_gl_close(ZRuntime *runtime) {
    ZGraphics *g=runtime->graphics;if(!g)return;
    g->provider.destroy(g->provider.user);
    for(unsigned i=0;i<g->extension_count;i++)free(g->extensions[i]);
    free(g->extension_string);
    for(ZGLString *s=g->strings;s;) { ZGLString *next=s->next;free(s);s=next; }
    free(g);runtime->graphics=NULL;
}
GLuint z_gl_framebuffer(struct w2c_a *h,GLuint object) {
    ZGraphics *g=graphics(h);return !object&&g->provider.framebuffer?g->provider.framebuffer(g->provider.user):object;
}
u64 z_gl_string(struct w2c_a *h,GLenum name,u32 index) {
    ZGraphics *g=graphics(h);for(ZGLString *s=g->strings;s;s=s->next)if(s->name==name&&s->index==index)return s->guest;
    const char *value=NULL;
    if(name==GL_EXTENSIONS) {
        if(index==UINT32_MAX)value=g->extension_string;
        else if(index<g->extension_count)value=g->extensions[index];
    } else if(index==UINT32_MAX)value=(const char *)glGetString(name);
    if(!value)return 0;
    ZGLString *s=calloc(1,sizeof *s);if(!s)wasm_rt_trap(WASM_RT_TRAP_EXHAUSTION);
    size_t bytes=strlen(value)+1;s->guest=Z_EXPORT_malloc(&h->engine,bytes);
    if(!s->guest){free(s);wasm_rt_trap(WASM_RT_TRAP_EXHAUSTION);}
    memcpy(z_pointer(h,s->guest,bytes),value,bytes);s->name=name;s->index=index;s->next=g->strings;g->strings=s;return s->guest;
}
static u32 state_count(struct w2c_a *h,GLenum name) {
    switch(name) {
    case GL_VIEWPORT:case GL_SCISSOR_BOX:case GL_BLEND_COLOR:case GL_COLOR_CLEAR_VALUE:case GL_COLOR_WRITEMASK:return 4;
    case GL_DEPTH_RANGE:case GL_ALIASED_LINE_WIDTH_RANGE:case GL_ALIASED_POINT_SIZE_RANGE:case GL_MAX_VIEWPORT_DIMS:return 2;
    case GL_COMPRESSED_TEXTURE_FORMATS:case GL_SHADER_BINARY_FORMATS:case GL_PROGRAM_BINARY_FORMATS: {
        GLint n=0;glGetIntegerv(name==GL_COMPRESSED_TEXTURE_FORMATS?GL_NUM_COMPRESSED_TEXTURE_FORMATS:
                             name==GL_SHADER_BINARY_FORMATS?GL_NUM_SHADER_BINARY_FORMATS:GL_NUM_PROGRAM_BINARY_FORMATS,&n);
        if(n<0||n>4096)z_missing(h,"unexpected GLES format-query count");
        return n;
    }
    default:return 1;
    }
}
void z_gl_get_state(struct w2c_a *h,GLenum name,u64 address,unsigned kind) {
    u32 count=state_count(h,name);ZGraphics *g=graphics(h);
    if(name==GL_NUM_EXTENSIONS) {
        switch(kind) {
        case 0: { GLboolean v=g->extension_count!=0;memcpy(z_pointer(h,address,1),&v,1);return; }
        case 1: { GLfloat v=g->extension_count;memcpy(z_pointer(h,address,4),&v,4);return; }
        case 2:z_write32(h,address,g->extension_count);return;
        case 3:z_write64(h,address,g->extension_count);return;
        }
    }
    switch(kind) {
    case 0:glGetBooleanv(name,z_pointer(h,address,count));break;
    case 1:glGetFloatv(name,z_pointer(h,address,4*count));break;
    case 2: {
        GLint *values=z_pointer(h,address,4*count);glGetIntegerv(name,values);
        if((name==GL_FRAMEBUFFER_BINDING||name==GL_READ_FRAMEBUFFER_BINDING)&&g->provider.framebuffer&&
            (GLuint)*values==g->provider.framebuffer(g->provider.user))*values=0;
        break;
    }
    case 3:glGetInteger64v(name,z_pointer(h,address,8*count));break;
    }
}
static unsigned uniform_components(GLenum type) {
    switch(type) {
    case GL_FLOAT_VEC2:case GL_INT_VEC2:case GL_UNSIGNED_INT_VEC2:case GL_BOOL_VEC2:return 2;
    case GL_FLOAT_VEC3:case GL_INT_VEC3:case GL_UNSIGNED_INT_VEC3:case GL_BOOL_VEC3:return 3;
    case GL_FLOAT_VEC4:case GL_INT_VEC4:case GL_UNSIGNED_INT_VEC4:case GL_BOOL_VEC4:case GL_FLOAT_MAT2:return 4;
    case GL_FLOAT_MAT2x3:case GL_FLOAT_MAT3x2:return 6;
    case GL_FLOAT_MAT2x4:case GL_FLOAT_MAT4x2:return 8;
    case GL_FLOAT_MAT3:return 9;
    case GL_FLOAT_MAT3x4:case GL_FLOAT_MAT4x3:return 12;
    case GL_FLOAT_MAT4:return 16;
    default:return 1;
    }
}
u32 z_gl_uniform_count(struct w2c_a *h,GLuint program,GLint location) {
    GLint count=0,max_name=0;glGetProgramiv(program,GL_ACTIVE_UNIFORMS,&count);glGetProgramiv(program,GL_ACTIVE_UNIFORM_MAX_LENGTH,&max_name);
    if(count<0||count>65536||max_name<0||max_name>1048576)z_missing(h,"unexpected GLES uniform metadata");
    char *name=calloc((size_t)max_name+32,1);if(!name)wasm_rt_trap(WASM_RT_TRAP_EXHAUSTION);
    for(GLint i=0;i<count;i++) {
        GLint size=0;GLenum type=0;glGetActiveUniform(program,i,max_name,NULL,&size,&type,name);
        if(glGetUniformLocation(program,name)==location) { free(name);return uniform_components(type); }
        // Elements of an active uniform array have individually queryable
        // locations. glGetUniform returns one array element for that location.
        char *bracket=strstr(name,"[0]");
        if(bracket&&size>1&&size<65536) {
            size_t prefix=bracket-name;char *suffix=strdup(bracket+3);
            for(GLint j=1;j<size;j++) {
                snprintf(name+prefix,(size_t)max_name+32-prefix,"[%d]%s",j,suffix?suffix:"");
                if(glGetUniformLocation(program,name)==location) { free(suffix);free(name);return uniform_components(type); }
            }
            free(suffix);
        }
    }
    free(name);return 1; // Invalid locations are rejected by the native driver.
}
u32 z_gl_block_count(struct w2c_a *h,GLuint program,GLuint block,GLenum name) {
    if(name!=GL_UNIFORM_BLOCK_ACTIVE_UNIFORM_INDICES)return 1;
    GLint count=0;glGetActiveUniformBlockiv(program,block,GL_UNIFORM_BLOCK_ACTIVE_UNIFORMS,&count);
    if(count<0||count>65536)z_missing(h,"unexpected GLES uniform-block count");
    return count;
}
GLsync z_gl_sync(struct w2c_a *h,u64 handle) {
    ZGraphics *g=graphics(h);if(!handle||handle>1024)return NULL;return g->syncs[handle-1];
}
u64 z_gl_sync_create(struct w2c_a *h,GLenum condition,GLbitfield flags) {
    ZGraphics *g=graphics(h);GLsync sync=glFenceSync(condition,flags);if(!sync)return 0;
    for(unsigned i=0;i<1024;i++)if(!g->syncs[i]) { g->syncs[i]=sync;return i+1; }
    glDeleteSync(sync);wasm_rt_trap(WASM_RT_TRAP_EXHAUSTION);
}
bool z_gl_sync_is(struct w2c_a *h,u64 handle) { GLsync sync=z_gl_sync(h,handle);return sync&&glIsSync(sync); }
void z_gl_sync_delete(struct w2c_a *h,u64 handle) {
    GLsync sync=z_gl_sync(h,handle);if(sync) { glDeleteSync(sync);graphics(h)->syncs[handle-1]=NULL; }
}
