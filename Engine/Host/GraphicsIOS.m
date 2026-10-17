#import <Foundation/Foundation.h>
#import <QuartzCore/CAEAGLLayer.h>
#import <OpenGLES/EAGL.h>
#include "Graphics.h"
#include <stdio.h>
#include <TargetConditionals.h>

// Draw at the selected game resolution, then scale into the phone drawable.
// A separate framebuffer preserves the engine's meaning of framebuffer zero.
@interface ZIOSGLES : NSObject {
@public
    GLuint drawableFramebuffer, drawableColor;
    GLuint gameFramebuffer, gameColor, gameDepth;
    GLuint copyProgram, copyVertexArray;
    GLint drawableWidth, drawableHeight;
    u32 gameWidth, gameHeight;
    unsigned presentedFrames;
}
@property(nonatomic,strong) CAEAGLLayer *layer;
@property(nonatomic,strong) EAGLContext *context;
@end
@implementation ZIOSGLES
@end

static bool resize(void *pointer,u32 width,u32 height) {
    ZIOSGLES *s=(__bridge ZIOSGLES *)pointer;
    GLint previous=0,texture=0,unpack=0;glGetIntegerv(GL_RENDERBUFFER_BINDING,&previous);
    glGetIntegerv(GL_TEXTURE_BINDING_2D,&texture);glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING,&unpack);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER,0);glBindTexture(GL_TEXTURE_2D,s->gameColor);
    glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,width,height,0,GL_RGBA,GL_UNSIGNED_BYTE,NULL);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
    glBindTexture(GL_TEXTURE_2D,texture);glBindBuffer(GL_PIXEL_UNPACK_BUFFER,unpack);
    glBindRenderbuffer(GL_RENDERBUFFER,s->gameDepth);glRenderbufferStorage(GL_RENDERBUFFER,GL_DEPTH24_STENCIL8,width,height);
    glBindRenderbuffer(GL_RENDERBUFFER,previous);
    if(glGetError()!=GL_NO_ERROR)return false;
    s->gameWidth=width;s->gameHeight=height;return true;
}
static GLuint copy_program(void) {
    const char *sources[]={
        "#version 300 es\nprecision highp float;out vec2 uv;void main(){vec2 p=gl_VertexID==0?vec2(-1.,-1.):(gl_VertexID==1?vec2(3.,-1.):vec2(-1.,3.));uv=p*.5+.5;gl_Position=vec4(p,0.,1.);}",
        "#version 300 es\nprecision highp float;in vec2 uv;uniform sampler2D frameTexture;out vec4 color;void main(){color=vec4(texture(frameTexture,uv).rgb,1.);}"};
    GLuint shaders[2]={0},program=0;GLint ok=0;
    for(unsigned i=0;i<2;i++) {
        shaders[i]=glCreateShader(i?GL_FRAGMENT_SHADER:GL_VERTEX_SHADER);glShaderSource(shaders[i],1,sources+i,NULL);glCompileShader(shaders[i]);
        glGetShaderiv(shaders[i],GL_COMPILE_STATUS,&ok);
        if(!ok){char log[1024]={0};glGetShaderInfoLog(shaders[i],sizeof log,NULL,log);fprintf(stderr,"[engine] iOS presentation shader: %s\n",log);goto done;}
    }
    program=glCreateProgram();glAttachShader(program,shaders[0]);glAttachShader(program,shaders[1]);glLinkProgram(program);glGetProgramiv(program,GL_LINK_STATUS,&ok);
    if(!ok){char log[1024]={0};glGetProgramInfoLog(program,sizeof log,NULL,log);fprintf(stderr,"[engine] iOS presentation program: %s\n",log);glDeleteProgram(program);program=0;}
done:
    for(unsigned i=0;i<2;i++)if(shaders[i])glDeleteShader(shaders[i]);
    return program;
}
static bool create(void *pointer,u32 width,u32 height) {
    @autoreleasepool {
        ZIOSGLES *s=(__bridge ZIOSGLES *)pointer;
        s.context=[[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
        if(!s.context||![EAGLContext setCurrentContext:s.context])return false;
        glGenFramebuffers(1,&s->drawableFramebuffer);glBindFramebuffer(GL_FRAMEBUFFER,s->drawableFramebuffer);
        glGenRenderbuffers(1,&s->drawableColor);glBindRenderbuffer(GL_RENDERBUFFER,s->drawableColor);
        if(![s.context renderbufferStorage:GL_RENDERBUFFER fromDrawable:s.layer])return false;
        glGetRenderbufferParameteriv(GL_RENDERBUFFER,GL_RENDERBUFFER_WIDTH,&s->drawableWidth);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER,GL_RENDERBUFFER_HEIGHT,&s->drawableHeight);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_RENDERBUFFER,s->drawableColor);
        if(glCheckFramebufferStatus(GL_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE)return false;
        glGenFramebuffers(1,&s->gameFramebuffer);glBindFramebuffer(GL_FRAMEBUFFER,s->gameFramebuffer);
        glGenTextures(1,&s->gameColor);glGenRenderbuffers(1,&s->gameDepth);
        if(!resize(pointer,width,height))return false;
        glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,s->gameColor,0);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_DEPTH_STENCIL_ATTACHMENT,GL_RENDERBUFFER,s->gameDepth);
        if(glCheckFramebufferStatus(GL_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE)return false;
        s->copyProgram=copy_program();if(!s->copyProgram)return false;
        glGenVertexArrays(1,&s->copyVertexArray);
        fprintf(stderr,"[engine] iOS GLES drawable %dx%d; game %ux%u\n",s->drawableWidth,s->drawableHeight,width,height);
        return true;
    }
}
static bool current(void *pointer,bool enabled) {
    ZIOSGLES *s=(__bridge ZIOSGLES *)pointer;return [EAGLContext setCurrentContext:enabled?s.context:nil];
}
#if TARGET_OS_SIMULATOR
static void capture_drawable(ZIOSGLES *s) {
    if(![NSProcessInfo.processInfo.arguments containsObject:@"--engine-smoke-test"])return;
    size_t count=(size_t)s->drawableWidth*s->drawableHeight;unsigned char *pixels=calloc(count,4);if(!pixels)return;
    GLint read,pack,alignment,row,rows,columns;glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&read);glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING,&pack);
    glGetIntegerv(GL_PACK_ALIGNMENT,&alignment);glGetIntegerv(GL_PACK_ROW_LENGTH,&row);glGetIntegerv(GL_PACK_SKIP_ROWS,&rows);glGetIntegerv(GL_PACK_SKIP_PIXELS,&columns);
    GLenum previous=glGetError();glBindFramebuffer(GL_READ_FRAMEBUFFER,s->drawableFramebuffer);glBindBuffer(GL_PIXEL_PACK_BUFFER,0);
    glPixelStorei(GL_PACK_ALIGNMENT,1);glPixelStorei(GL_PACK_ROW_LENGTH,0);glPixelStorei(GL_PACK_SKIP_ROWS,0);glPixelStorei(GL_PACK_SKIP_PIXELS,0);
    glReadPixels(0,0,s->drawableWidth,s->drawableHeight,GL_RGBA,GL_UNSIGNED_BYTE,pixels);GLenum error=glGetError();
    unsigned lit=0;for(size_t i=0;i<count;i++)if(pixels[4*i]||pixels[4*i+1]||pixels[4*i+2])lit++;
    fprintf(stderr,"[iOS display] drawable lit=%u/%zu previousGL=0x%x readGL=0x%x layerHidden=%d opacity=%g\n",lit,count,previous,error,s.layer.hidden,s.layer.opacity);
    NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/engine-drawable.ppm"];FILE *file=fopen(path.fileSystemRepresentation,"wb");
    if(file){fprintf(file,"P6\n%d %d\n255\n",s->drawableWidth,s->drawableHeight);for(GLint y=s->drawableHeight;y>0;y--)for(GLint x=0;x<s->drawableWidth;x++)fwrite(pixels+((size_t)(y-1)*s->drawableWidth+x)*4,1,3,file);fclose(file);}
    free(pixels);glBindFramebuffer(GL_READ_FRAMEBUFFER,read);glBindBuffer(GL_PIXEL_PACK_BUFFER,pack);
    glPixelStorei(GL_PACK_ALIGNMENT,alignment);glPixelStorei(GL_PACK_ROW_LENGTH,row);glPixelStorei(GL_PACK_SKIP_ROWS,rows);glPixelStorei(GL_PACK_SKIP_PIXELS,columns);
}
#endif
static bool present(void *pointer) {
    @autoreleasepool {
        ZIOSGLES *s=(__bridge ZIOSGLES *)pointer;
        GLint draw=0,renderbuffer=0,program=0,vao=0,active=0,texture=0,sampler=0,viewport[4];
        glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&draw);glGetIntegerv(GL_RENDERBUFFER_BINDING,&renderbuffer);
        glGetIntegerv(GL_CURRENT_PROGRAM,&program);glGetIntegerv(GL_VERTEX_ARRAY_BINDING,&vao);glGetIntegerv(GL_VIEWPORT,viewport);
        glGetIntegerv(GL_ACTIVE_TEXTURE,&active);glActiveTexture(GL_TEXTURE0);glGetIntegerv(GL_TEXTURE_BINDING_2D,&texture);glGetIntegerv(GL_SAMPLER_BINDING,&sampler);
        const GLenum features[]={GL_SCISSOR_TEST,GL_BLEND,GL_CULL_FACE,GL_DEPTH_TEST,GL_STENCIL_TEST,GL_RASTERIZER_DISCARD,GL_SAMPLE_COVERAGE,GL_SAMPLE_ALPHA_TO_COVERAGE};
        GLboolean enabled[sizeof features/sizeof *features];
        for(unsigned i=0;i<sizeof features/sizeof *features;i++){enabled[i]=glIsEnabled(features[i]);glDisable(features[i]);}
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER,s->drawableFramebuffer);
        GLfloat clear[4];GLboolean mask[4];glGetFloatv(GL_COLOR_CLEAR_VALUE,clear);glGetBooleanv(GL_COLOR_WRITEMASK,mask);
        glColorMask(GL_TRUE,GL_TRUE,GL_TRUE,GL_TRUE);glClearColor(0,0,0,1);glClear(GL_COLOR_BUFFER_BIT);
        double sx=(double)s->drawableWidth/s->gameWidth,sy=(double)s->drawableHeight/s->gameHeight,scale=sx<sy?sx:sy;
        GLint width=(GLint)(s->gameWidth*scale+0.5),height=(GLint)(s->gameHeight*scale+0.5);
        GLint x=(s->drawableWidth-width)/2,y=(s->drawableHeight-height)/2;
        // Sample the game target into the drawable using a normal ES draw.
        // This also gives the opaque canvas its required alpha of one.
        glViewport(x,y,width,height);glUseProgram(s->copyProgram);glBindVertexArray(s->copyVertexArray);
        glBindSampler(0,0);glBindTexture(GL_TEXTURE_2D,s->gameColor);glUniform1i(glGetUniformLocation(s->copyProgram,"frameTexture"),0);
        glDrawArrays(GL_TRIANGLES,0,3);
        #if TARGET_OS_SIMULATOR
        if(++s->presentedFrames==60)capture_drawable(s);
        #endif
        glColorMask(mask[0],mask[1],mask[2],mask[3]);glClearColor(clear[0],clear[1],clear[2],clear[3]);
        glUseProgram(program);glBindVertexArray(vao);glViewport(viewport[0],viewport[1],viewport[2],viewport[3]);
        glBindTexture(GL_TEXTURE_2D,texture);glBindSampler(0,sampler);glActiveTexture(active);
        for(unsigned i=0;i<sizeof features/sizeof *features;i++)if(enabled[i])glEnable(features[i]);
        glBindRenderbuffer(GL_RENDERBUFFER,s->drawableColor);bool ok=[s.context presentRenderbuffer:GL_RENDERBUFFER];
        glBindRenderbuffer(GL_RENDERBUFFER,renderbuffer);glBindFramebuffer(GL_DRAW_FRAMEBUFFER,draw);
        return ok;
    }
}
static GLuint framebuffer(void *pointer) { return ((__bridge ZIOSGLES *)pointer)->gameFramebuffer; }
static void destroy(void *pointer) {
    @autoreleasepool {
        ZIOSGLES *s=CFBridgingRelease(pointer);
        if(s.context) {
            [EAGLContext setCurrentContext:s.context];
            glDeleteFramebuffers(1,&s->gameFramebuffer);glDeleteFramebuffers(1,&s->drawableFramebuffer);
            glDeleteRenderbuffers(1,&s->drawableColor);glDeleteTextures(1,&s->gameColor);glDeleteRenderbuffers(1,&s->gameDepth);
            glDeleteProgram(s->copyProgram);glDeleteVertexArrays(1,&s->copyVertexArray);
            [EAGLContext setCurrentContext:nil];s.context=nil;
        }
    }
}
bool z_gl_ios_attach(ZRuntime *runtime,void *layer) {
    if(![NSThread isMainThread]||!layer||![(__bridge id)layer isKindOfClass:CAEAGLLayer.class])return false;
    ZIOSGLES *s=[ZIOSGLES new];s.layer=(__bridge CAEAGLLayer *)layer;
    void *retained=(void *)CFBridgingRetain(s);
    if(!z_gl_attach(runtime,(ZGraphicsProvider){.user=retained,.create=create,.current=current,.present=present,.resize=resize,.framebuffer=framebuffer,.destroy=destroy})) {
        CFRelease(retained);return false;
    }
    return true;
}
