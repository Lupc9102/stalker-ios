#import <Foundation/Foundation.h>
#import <QuartzCore/CAEAGLLayer.h>
#import <OpenGLES/EAGL.h>
#include "Graphics.h"
#include <stdio.h>

// Draw at the selected game resolution, then scale into the phone drawable.
// A separate framebuffer preserves the engine's meaning of framebuffer zero.
@interface ZIOSGLES : NSObject {
@public
    GLuint drawableFramebuffer, drawableColor;
    GLuint gameFramebuffer, gameColor, gameDepth;
    GLint drawableWidth, drawableHeight;
    u32 gameWidth, gameHeight;
}
@property(nonatomic,strong) CAEAGLLayer *layer;
@property(nonatomic,strong) EAGLContext *context;
@end
@implementation ZIOSGLES
@end

static bool resize(void *pointer,u32 width,u32 height) {
    ZIOSGLES *s=(__bridge ZIOSGLES *)pointer;
    GLint previous=0;glGetIntegerv(GL_RENDERBUFFER_BINDING,&previous);
    glBindRenderbuffer(GL_RENDERBUFFER,s->gameColor);glRenderbufferStorage(GL_RENDERBUFFER,GL_RGBA8,width,height);
    glBindRenderbuffer(GL_RENDERBUFFER,s->gameDepth);glRenderbufferStorage(GL_RENDERBUFFER,GL_DEPTH24_STENCIL8,width,height);
    glBindRenderbuffer(GL_RENDERBUFFER,previous);
    if(glGetError()!=GL_NO_ERROR)return false;
    s->gameWidth=width;s->gameHeight=height;return true;
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
        glGenRenderbuffers(1,&s->gameColor);glGenRenderbuffers(1,&s->gameDepth);
        if(!resize(pointer,width,height))return false;
        glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_RENDERBUFFER,s->gameColor);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_DEPTH_STENCIL_ATTACHMENT,GL_RENDERBUFFER,s->gameDepth);
        if(glCheckFramebufferStatus(GL_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE)return false;
        fprintf(stderr,"[engine] iOS GLES drawable %dx%d; game %ux%u\n",s->drawableWidth,s->drawableHeight,width,height);
        return true;
    }
}
static bool current(void *pointer,bool enabled) {
    ZIOSGLES *s=(__bridge ZIOSGLES *)pointer;return [EAGLContext setCurrentContext:enabled?s.context:nil];
}
static bool present(void *pointer) {
    @autoreleasepool {
        ZIOSGLES *s=(__bridge ZIOSGLES *)pointer;
        GLint read=0,draw=0,renderbuffer=0;
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&read);glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&draw);
        glGetIntegerv(GL_RENDERBUFFER_BINDING,&renderbuffer);GLboolean scissor=glIsEnabled(GL_SCISSOR_TEST);
        glDisable(GL_SCISSOR_TEST);glBindFramebuffer(GL_READ_FRAMEBUFFER,s->gameFramebuffer);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER,s->drawableFramebuffer);
        GLfloat clear[4];GLboolean mask[4];glGetFloatv(GL_COLOR_CLEAR_VALUE,clear);glGetBooleanv(GL_COLOR_WRITEMASK,mask);
        glColorMask(GL_TRUE,GL_TRUE,GL_TRUE,GL_TRUE);glClearColor(0,0,0,1);glClear(GL_COLOR_BUFFER_BIT);
        glColorMask(mask[0],mask[1],mask[2],mask[3]);glClearColor(clear[0],clear[1],clear[2],clear[3]);
        double sx=(double)s->drawableWidth/s->gameWidth,sy=(double)s->drawableHeight/s->gameHeight,scale=sx<sy?sx:sy;
        GLint width=(GLint)(s->gameWidth*scale+0.5),height=(GLint)(s->gameHeight*scale+0.5);
        GLint x=(s->drawableWidth-width)/2,y=(s->drawableHeight-height)/2;
        glBlitFramebuffer(0,0,s->gameWidth,s->gameHeight,x,y,x+width,y+height,GL_COLOR_BUFFER_BIT,GL_LINEAR);
        glBindRenderbuffer(GL_RENDERBUFFER,s->drawableColor);bool ok=[s.context presentRenderbuffer:GL_RENDERBUFFER];
        glBindRenderbuffer(GL_RENDERBUFFER,renderbuffer);glBindFramebuffer(GL_READ_FRAMEBUFFER,read);glBindFramebuffer(GL_DRAW_FRAMEBUFFER,draw);
        if(scissor)glEnable(GL_SCISSOR_TEST);
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
            glDeleteRenderbuffers(1,&s->drawableColor);glDeleteRenderbuffers(1,&s->gameColor);glDeleteRenderbuffers(1,&s->gameDepth);
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
