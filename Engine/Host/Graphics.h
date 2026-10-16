#pragma once
#include "Host.h"
#if defined(__APPLE__)
#include <OpenGLES/ES3/gl.h>
#else
#include <GLES3/gl3.h>
#endif

// The graphics provider owns its drawable and context. All callbacks execute
// on the engine thread, including present. UIKit creates its layer on main.
typedef struct {
    void *user;
    bool (*create)(void *, u32, u32);
    bool (*current)(void *, bool);
    bool (*present)(void *);
    void (*destroy)(void *);
    GLuint (*framebuffer)(void *);
} ZGraphicsProvider;
bool z_gl_attach(ZRuntime *, ZGraphicsProvider);
void z_gl_close(ZRuntime *);
bool z_gl_present(struct w2c_a *);
void z_gl_require(struct w2c_a *);
u64 z_gl_count(struct w2c_a *, u64, u64);
void *z_gl_optional(struct w2c_a *, u64, u64);
const GLchar **z_gl_strings(struct w2c_a *, u64, u64, u32);
const void *z_gl_buffer_offset(struct w2c_a *, GLenum, u64);
void *z_gl_pixels(struct w2c_a *, u64, u32, u32, u32, GLenum, GLenum, bool, bool);
void *z_gl_pixel_bytes(struct w2c_a *, u64, u32, bool);
void z_gl_get_state(struct w2c_a *, GLenum, u64, unsigned);
u32 z_gl_uniform_count(struct w2c_a *, GLuint, GLint);
u32 z_gl_block_count(struct w2c_a *, GLuint, GLuint, GLenum);
u64 z_gl_string(struct w2c_a *, GLenum, u32);
GLuint z_gl_framebuffer(struct w2c_a *, GLuint);
GLsync z_gl_sync(struct w2c_a *, u64);
u64 z_gl_sync_create(struct w2c_a *, GLenum, GLbitfield);
bool z_gl_sync_is(struct w2c_a *, u64);
void z_gl_sync_delete(struct w2c_a *, u64);
#if !defined(__APPLE__)
bool z_gl_egl_attach(ZRuntime *);
#endif
