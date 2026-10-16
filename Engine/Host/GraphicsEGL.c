#include "Graphics.h"
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct { EGLDisplay display; EGLContext context; EGLSurface surface; } ZEGL;
static bool create(void *user,u32 width,u32 height) {
    ZEGL *e=user;
    PFNEGLGETPLATFORMDISPLAYEXTPROC platform=(PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
    e->display=platform?platform(EGL_PLATFORM_SURFACELESS_MESA,EGL_DEFAULT_DISPLAY,NULL):eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if(e->display==EGL_NO_DISPLAY||!eglInitialize(e->display,NULL,NULL)||!eglBindAPI(EGL_OPENGL_ES_API))return false;
    EGLint attributes[]={EGL_SURFACE_TYPE,EGL_PBUFFER_BIT,EGL_RENDERABLE_TYPE,EGL_OPENGL_ES3_BIT,
      EGL_RED_SIZE,8,EGL_GREEN_SIZE,8,EGL_BLUE_SIZE,8,EGL_ALPHA_SIZE,8,EGL_DEPTH_SIZE,24,EGL_STENCIL_SIZE,8,EGL_NONE};
    EGLConfig config;EGLint count=0;
    if(!eglChooseConfig(e->display,attributes,&config,1,&count)||count!=1)return false;
    EGLint dimensions[]={EGL_WIDTH,(EGLint)width,EGL_HEIGHT,(EGLint)height,EGL_NONE};
    EGLint version[]={EGL_CONTEXT_CLIENT_VERSION,3,EGL_NONE};
    e->surface=eglCreatePbufferSurface(e->display,config,dimensions);
    e->context=eglCreateContext(e->display,config,EGL_NO_CONTEXT,version);
    if(e->surface==EGL_NO_SURFACE||e->context==EGL_NO_CONTEXT) { fprintf(stderr,"[engine] EGL create error 0x%x\n",eglGetError());return false; }
    return true;
}
static bool current(void *user,bool enabled) {
    ZEGL *e=user;return eglMakeCurrent(e->display,enabled?e->surface:EGL_NO_SURFACE,
                                     enabled?e->surface:EGL_NO_SURFACE,enabled?e->context:EGL_NO_CONTEXT)==EGL_TRUE;
}
static bool present(void *user) { ZEGL *e=user;return eglSwapBuffers(e->display,e->surface)==EGL_TRUE; }
static void destroy(void *user) {
    ZEGL *e=user;eglMakeCurrent(e->display,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT);
    if(e->context)eglDestroyContext(e->display,e->context);
    if(e->surface)eglDestroySurface(e->display,e->surface);
    if(e->display)eglTerminate(e->display);
    free(e);
}
bool z_gl_egl_attach(ZRuntime *runtime) {
    ZEGL *e=calloc(1,sizeof *e);if(!e)return false;
    if(!z_gl_attach(runtime,(ZGraphicsProvider){.user=e,.create=create,.current=current,.present=present,.destroy=destroy})) { free(e);return false; }
    return true;
}
