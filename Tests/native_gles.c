#include "Graphics.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static u32 word(struct w2c_a *h,u64 p) { u32 value;memcpy(&value,z_pointer(h,p,4),4);return value; }
static u64 text(struct w2c_a *h,const char *value) {
    size_t bytes=strlen(value)+1;u64 p=Z_EXPORT_malloc(&h->engine,bytes);assert(p);
    memcpy(z_pointer(h,p,bytes),value,bytes);return p;
}
static GLuint shader(struct w2c_a *h,GLenum kind,const char *source,u64 scratch) {
    GLuint object=Z_IMPORT_glCreateShader(h,kind);assert(object);
    u64 string=text(h,source),high=((u64)1<<32)+1024;
    memcpy(z_pointer(h,high,strlen(source)+1),source,strlen(source)+1);z_write64(h,scratch,high);
    Z_IMPORT_glShaderSource(h,object,1,scratch,0);Z_IMPORT_glCompileShader(h,object);
    Z_IMPORT_glGetShaderiv(h,object,GL_COMPILE_STATUS,scratch+16);
    if(!word(h,scratch+16)) { Z_IMPORT_glGetShaderInfoLog(h,object,2048,0,scratch+32);fprintf(stderr,"%s\n",z_string(h,scratch+32)); }
    assert(word(h,scratch+16));Z_EXPORT_free(&h->engine,string);return object;
}
int main(int argc,char **argv) {
    wasm_rt_init();ZRuntime *rt=calloc(1,sizeof *rt);struct w2c_a *h=calloc(1,sizeof *h);assert(rt&&h);
    h->runtime=rt;rt->threads=h;rt->width=256;rt->height=256;pthread_mutex_init(&rt->lock,NULL);z_current_thread=h;
    assert(z_memory_open(rt,5120));
    assert(wasm_rt_impl_try()==WASM_RT_TRAP_NONE);wasm2c_xray_instantiate(&h->engine,h);w2c_xray_fi(&h->engine);
    u64 p=Z_EXPORT_malloc(&h->engine,256*256*4+8192);assert(p);memset(z_pointer(h,p,64),0,64);z_write32(h,p+16,2);
    assert(z_gl_egl_attach(rt));assert(Z_IMPORT_emscripten_webgl_create_context(h,0,p)==1);
    assert(Z_IMPORT_emscripten_webgl_make_context_current(h,1)==0);
    // GLAD obtains its procedures from this guest table. Calling imports
    // directly would miss a namespace-binding bug in the generated engine.
    wasm_rt_funcref_table_t *table=Z_EXPORT__indirect_function_table(&h->engine);
    wasm_rt_funcref_t error=table->data[Z_TABLE_emscripten_glGetError];
    assert(error.module_instance==h);
    assert(((u32 (*)(void *))error.func)(error.module_instance)==GL_NO_ERROR);
    u64 renderer=Z_IMPORT_glGetString(h,GL_RENDERER);assert(renderer);printf("GPU renderer: %s\n",z_string(h,renderer));
    assert(Z_IMPORT_glGetString(h,GL_RENDERER)==renderer);
    u64 scratch=p+128;
    GLuint vs=shader(h,GL_VERTEX_SHADER,"#version 300 es\nlayout(location=0) in vec2 pos;void main(){gl_Position=vec4(pos,0.,1.);}",scratch);
    GLuint fs=shader(h,GL_FRAGMENT_SHADER,"#version 300 es\nprecision highp float;uniform vec4 tint;out vec4 color;void main(){color=tint;}",scratch);
    GLuint program=Z_IMPORT_glCreateProgram(h);Z_IMPORT_glAttachShader(h,program,vs);Z_IMPORT_glAttachShader(h,program,fs);Z_IMPORT_glLinkProgram(h,program);
    Z_IMPORT_glGetProgramiv(h,program,GL_LINK_STATUS,scratch);assert(word(h,scratch));Z_IMPORT_glUseProgram(h,program);
    u64 name=text(h,"tint");GLint uniform=(GLint)Z_IMPORT_glGetUniformLocation(h,program,name);assert(uniform>=0);
    const GLfloat tint[]={1,.45f,.08f,1};memcpy(z_pointer(h,scratch,16),tint,16);Z_IMPORT_emscripten_glUniform4fv(h,uniform,1,scratch);
    Z_IMPORT_emscripten_glGetUniformfv(h,program,uniform,scratch+32);assert(!memcmp(z_pointer(h,scratch+32,16),tint,16));
    Z_IMPORT_glGenVertexArrays(h,1,scratch);GLuint vao=word(h,scratch);Z_IMPORT_glBindVertexArray(h,vao);
    Z_IMPORT_glGenBuffers(h,1,scratch+4);GLuint buffer=word(h,scratch+4);Z_IMPORT_glBindBuffer(h,GL_ARRAY_BUFFER,buffer);
    const GLfloat points[]={-.8f,-.7f,.8f,-.7f,0,.8f};u64 vertices=((u64)1<<32)+512;
    memcpy(z_pointer(h,vertices,sizeof points),points,sizeof points);
    Z_IMPORT_glBufferData(h,GL_ARRAY_BUFFER,sizeof points,vertices,GL_STATIC_DRAW);
    Z_IMPORT_glVertexAttribPointer(h,0,2,GL_FLOAT,GL_FALSE,0,0);Z_IMPORT_glEnableVertexAttribArray(h,0);
    Z_IMPORT_emscripten_glGetVertexAttribPointerv(h,0,GL_VERTEX_ATTRIB_ARRAY_POINTER,scratch+104);assert(z_read64(h,scratch+104)==0);
    Z_IMPORT_glViewport(h,0,0,256,256);Z_IMPORT_glGetIntegerv(h,GL_VIEWPORT,scratch+112);assert(word(h,scratch+120)==256&&word(h,scratch+124)==256);
    Z_IMPORT_glClearColor(h,.025f,.055f,.08f,1);Z_IMPORT_glClear(h,GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
    Z_IMPORT_emscripten_glDrawArrays(h,GL_TRIANGLES,0,3);assert(Z_IMPORT_emscripten_glGetError(h)==GL_NO_ERROR);
    // Pixel storage deliberately includes padding and skipped pixels. Verify
    // bounds calculation against an actual driver write, not a mock GL call.
    Z_IMPORT_emscripten_glPixelStorei(h,GL_PACK_ROW_LENGTH,260);Z_IMPORT_emscripten_glPixelStorei(h,GL_PACK_SKIP_PIXELS,2);
    u64 pixels=p+4096;Z_IMPORT_emscripten_glReadPixels(h,120,120,1,1,GL_RGBA,GL_UNSIGNED_BYTE,pixels);
    unsigned char *center=z_pointer(h,pixels+8,4);assert(center[0]>250&&center[1]>100&&center[1]<130&&center[2]<30);
    Z_IMPORT_emscripten_glPixelStorei(h,GL_PACK_ROW_LENGTH,0);Z_IMPORT_emscripten_glPixelStorei(h,GL_PACK_SKIP_PIXELS,0);
    Z_IMPORT_emscripten_glReadPixels(h,0,0,256,256,GL_RGBA,GL_UNSIGNED_BYTE,pixels);assert(Z_IMPORT_emscripten_glGetError(h)==GL_NO_ERROR);
    if(argc>1) {
        FILE *image=fopen(argv[1],"wb");assert(image);fprintf(image,"P6\n256 256\n255\n");
        unsigned char *bytes=z_pointer(h,pixels,256*256*4);
        for(int y=255;y>=0;y--)for(int x=0;x<256;x++)assert(fwrite(bytes+4*(y*256+x),1,3,image)==3);
        assert(!fclose(image));
    }
    u64 sync=Z_IMPORT_emscripten_glFenceSync(h,GL_SYNC_GPU_COMMANDS_COMPLETE,0);assert(sync&&Z_IMPORT_emscripten_glIsSync(h,sync));
    GLenum wait=Z_IMPORT_emscripten_glClientWaitSync(h,sync,GL_SYNC_FLUSH_COMMANDS_BIT,1000000000);
    assert(wait==GL_ALREADY_SIGNALED||wait==GL_CONDITION_SATISFIED);
    Z_IMPORT_emscripten_glDeleteSync(h,sync);assert(!Z_IMPORT_emscripten_glIsSync(h,sync));assert(z_gl_present(h));
    Z_IMPORT_glDeleteProgram(h,program);Z_IMPORT_glDeleteShader(h,vs);Z_IMPORT_glDeleteShader(h,fs);
    z_write32(h,scratch,buffer);Z_IMPORT_glDeleteBuffers(h,1,scratch);z_write32(h,scratch,vao);Z_IMPORT_glDeleteVertexArrays(h,1,scratch);
    assert(Z_IMPORT_emscripten_glGetError(h)==GL_NO_ERROR);
    z_gl_close(rt);Z_EXPORT_free(&h->engine,name);Z_EXPORT_free(&h->engine,p);
    wasm2c_xray_free(&h->engine);z_memory_close(rt);pthread_mutex_destroy(&rt->lock);free(h);free(rt);wasm_rt_free();
    puts("Native GLES: memory64 shader strings, shader compile/link, uniforms/reflection, vertex buffers, rasterization, pixel packing/readback, opaque sync handles and cleanup passed.");
    return 0;
}
