#define _POSIX_C_SOURCE 200809L
#include "Host.h"
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// OPFS handles are replaced by directory-relative descriptors. Retail files are
// opened read-only; modifications go to a separate copy-on-write overlay.
typedef struct {
    int type, read_fd, write_fd, parent_fd;
    unsigned references;
    dev_t parent_device;ino_t parent_inode;
    char *name;
} ZFile;
struct ZFilesystem { pthread_mutex_t mutex; ZFile **handles;u32 *free_ids;size_t count, capacity, free_count; };
static void finish(struct w2c_a *h,u64 ctx) { if(ctx)Z_EXPORT_emscripten_proxy_finish(&h->engine,ctx); }
static int error_code(void) {
    switch(errno) {case ENOENT:return -44;case ENOTDIR:return -54;case EISDIR:return -31;case EACCES:case EPERM:return -2;case ENOSPC:return -51;case EEXIST:return -20;default:return -29;}
}
static bool component(const char *name) { return *name&&strcmp(name,".")&&strcmp(name,"..")&&!strchr(name,'/')&&!strchr(name,'\\'); }
static int insert(ZFilesystem *fs,ZFile *entry) {
    if(fs->free_count){u32 id=fs->free_ids[--fs->free_count];fs->handles[id]=entry;if(entry)entry->references++;return (int)id;}
    if(fs->count>=65536)return -33;
    if(fs->count==fs->capacity) {
        size_t n=fs->capacity?fs->capacity*2:64;ZFile **next=realloc(fs->handles,n*sizeof *next);
        if(!next)return -48;
        fs->handles=next;
        u32 *ids=realloc(fs->free_ids,n*sizeof *ids);if(!ids)return -48;
        fs->free_ids=ids;fs->capacity=n;
    }
    fs->handles[fs->count]=entry;if(entry)entry->references++;return (int)fs->count++;
}
static ZFile *lookup(ZFilesystem *fs,u32 id,int type) {
    if(id>=fs->count||!fs->handles[id]||(type&&fs->handles[id]->type!=type))return NULL;
    return fs->handles[id];
}
static void release(ZFilesystem *fs,u32 id) {
    ZFile *f=lookup(fs,id,0);if(!f||id==1)return;
    fs->handles[id]=NULL;fs->free_ids[fs->free_count++]=id;
    if(--f->references)return;
    if(f->read_fd>=0)close(f->read_fd);
    if(f->write_fd>=0)close(f->write_fd);
    if(f->parent_fd>=0)close(f->parent_fd);
    free(f->name);free(f);
}
ZFilesystem *z_files_open(const char *root,const char *overlay) {
    ZFilesystem *fs=calloc(1,sizeof *fs);ZFile *dir=calloc(1,sizeof *dir);
    if(!fs||!dir){free(fs);free(dir);return NULL;}
    dir->read_fd=open(root,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    dir->write_fd=open(overlay,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);dir->parent_fd=-1;dir->type=2;
    if(dir->read_fd<0||dir->write_fd<0){perror("Native game/overlay folder");if(dir->read_fd>=0)close(dir->read_fd);if(dir->write_fd>=0)close(dir->write_fd);free(dir);free(fs);return NULL;}
    struct stat a,b;fstat(dir->read_fd,&a);fstat(dir->write_fd,&b);
    if(a.st_dev==b.st_dev&&a.st_ino==b.st_ino){fprintf(stderr,"Game folder and writable overlay must be different\n");close(dir->read_fd);close(dir->write_fd);free(dir);free(fs);return NULL;}
    pthread_mutex_init(&fs->mutex,NULL);insert(fs,NULL);insert(fs,dir);return fs;
}
void z_files_close(ZFilesystem *fs) {
    if(!fs)return;
    for(u32 i=2;i<fs->count;i++)release(fs,i);
    ZFile *root=fs->handles[1];close(root->read_fd);close(root->write_fd);free(root);
    free(fs->handles);free(fs->free_ids);pthread_mutex_destroy(&fs->mutex);free(fs);
}
static int child(ZFilesystem *fs,u32 parent,const char *name,bool create,bool directory) {
    if(!component(name))return -28;
    ZFile *dir=lookup(fs,parent,2);if(!dir)return -54;
    struct stat parent_info;if(fstat(dir->write_fd,&parent_info))return -29;
    for(size_t i=2;i<fs->count;i++) {
        ZFile *old=fs->handles[i];
        if(old&&old->name&&old->parent_device==parent_info.st_dev&&old->parent_inode==parent_info.st_ino&&!strcmp(old->name,name)) {
            if(old->type!=(directory?2:1))return old->type==2?-31:-54;
            return insert(fs,old);
        }
    }
    int flags=O_RDONLY|O_NOFOLLOW|O_CLOEXEC|(directory?O_DIRECTORY:0),ro=-1,rw=-1;
    if(dir->read_fd>=0)ro=openat(dir->read_fd,name,flags);
    int saved=errno;
    if(dir->write_fd>=0)rw=openat(dir->write_fd,name,flags);
    if(ro<0&&rw<0&&!create){errno=saved;return error_code();}
    if(directory) {
        if(rw<0) {
            if(mkdirat(dir->write_fd,name,0700)<0&&errno!=EEXIST){if(ro>=0)close(ro);return error_code();}
            rw=openat(dir->write_fd,name,flags);
        }
    } else if(create&&ro<0&&rw<0)rw=openat(dir->write_fd,name,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    int fd=rw>=0?rw:ro;struct stat st={0};
    if(fd<0||fstat(fd,&st)<0||(directory?!S_ISDIR(st.st_mode):!S_ISREG(st.st_mode))) {
        int e=fd>=0?(S_ISDIR(st.st_mode)?-31:-29):error_code();if(ro>=0)close(ro);if(rw>=0)close(rw);return e;
    }
    ZFile *f=calloc(1,sizeof *f);if(!f){if(ro>=0)close(ro);if(rw>=0)close(rw);return -48;}
    f->type=directory?2:1;f->read_fd=ro;f->write_fd=rw;f->parent_fd=dup(dir->write_fd);f->name=strdup(name);
    f->parent_device=parent_info.st_dev;f->parent_inode=parent_info.st_ino;
    int id=insert(fs,f);if(id<0){if(ro>=0)close(ro);if(rw>=0)close(rw);close(f->parent_fd);free(f->name);free(f);}return id;
}
static int readable(ZFile *f) { return f?(f->write_fd>=0?f->write_fd:f->read_fd):-1; }
static int writable(ZFile *f) {
    if(!f||f->type!=1){errno=EBADF;return -1;}
    // Reopen the overlay using the retained, sandboxed parent directory.
    int out=openat(f->parent_fd,f->name,O_RDWR|O_NOFOLLOW|O_CLOEXEC);
    if(out<0&&errno==ENOENT) {
        out=openat(f->parent_fd,f->name,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
        if(out>=0&&f->read_fd>=0) {
            unsigned char buffer[65536];off_t at=0;ssize_t n;
            while((n=pread(f->read_fd,buffer,sizeof buffer,at))>0) {
                ssize_t done=0;while(done<n){ssize_t w=pwrite(out,buffer+done,(size_t)(n-done),at+done);if(w<0&&errno==EINTR)continue;if(w<=0){close(out);unlinkat(f->parent_fd,f->name,0);return -1;}done+=w;}at+=n;
            }
            if(n<0){close(out);unlinkat(f->parent_fd,f->name,0);return -1;}
        }
    }
    if(out>=0){if(f->write_fd>=0)close(f->write_fd);f->write_fd=out;}return out;
}
static u64 size_of(ZFile *f) { struct stat s;int fd=readable(f);return fd>=0&&fstat(fd,&s)==0?(u64)s.st_size:(u64)-29; }
void Z_IMPORT__wasmfs_opfs_init_root_directory(struct w2c_a *h,u64 ctx) { finish(h,ctx); }
void Z_IMPORT__wasmfs_opfs_get_child(struct w2c_a *h,u64 ctx,u32 parent,u64 name,u64 type,u64 id) {
    ZFilesystem *fs=h->runtime->files;pthread_mutex_lock(&fs->mutex);
    int result=child(fs,parent,z_string(h,name),false,false);u32 kind=1;
    if(result==-31){kind=2;result=child(fs,parent,z_string(h,name),false,true);}
    z_write32(h,type,kind);z_write32(h,id,(u32)result);pthread_mutex_unlock(&fs->mutex);finish(h,ctx);
}
void Z_IMPORT__wasmfs_opfs_insert_directory(struct w2c_a *h,u64 ctx,u32 parent,u64 name,u64 id) {
    ZFilesystem *fs=h->runtime->files;pthread_mutex_lock(&fs->mutex);
    z_write32(h,id,(u32)child(fs,parent,z_string(h,name),true,true));pthread_mutex_unlock(&fs->mutex);finish(h,ctx);
}
void Z_IMPORT__wasmfs_opfs_insert_file(struct w2c_a *h,u64 ctx,u32 parent,u64 name,u64 id) {
    ZFilesystem *fs=h->runtime->files;pthread_mutex_lock(&fs->mutex);
    z_write32(h,id,(u32)child(fs,parent,z_string(h,name),true,false));pthread_mutex_unlock(&fs->mutex);finish(h,ctx);
}
static void open_copy(struct w2c_a *h,u64 ctx,u32 id,u64 out) {
    ZFilesystem *fs=h->runtime->files;pthread_mutex_lock(&fs->mutex);ZFile *old=lookup(fs,id,1);int result=-8;
    if(old)result=insert(fs,old);
    z_write32(h,out,(u32)result);pthread_mutex_unlock(&fs->mutex);finish(h,ctx);
}
void Z_IMPORT__wasmfs_opfs_open_access(struct w2c_a *h,u64 ctx,u32 id,u64 out) { open_copy(h,ctx,id,out); }
void Z_IMPORT__wasmfs_opfs_open_blob(struct w2c_a *h,u64 ctx,u32 id,u64 out) { open_copy(h,ctx,id,out); }
u32 Z_IMPORT__wasmfs_opfs_read_access(struct w2c_a *h,u32 id,u64 p,u32 bytes,u64 offset) {
    void *buffer=z_pointer(h,p,bytes);ZFilesystem *fs=h->runtime->files;pthread_mutex_lock(&fs->mutex);
    int fd=readable(lookup(fs,id,1));ssize_t n=fd>=0?pread(fd,buffer,bytes,(off_t)offset):-1;
    u32 result=n<0?(u32)-29:(u32)n;pthread_mutex_unlock(&fs->mutex);return result;
}
u32 Z_IMPORT__wasmfs_opfs_read_blob(struct w2c_a *h,u64 ctx,u32 id,u64 p,u32 bytes,u64 offset,u64 out) {
    z_write32(h,out,Z_IMPORT__wasmfs_opfs_read_access(h,id,p,bytes,offset));finish(h,ctx);return 0;
}
u32 Z_IMPORT__wasmfs_opfs_write_access(struct w2c_a *h,u32 id,u64 p,u32 bytes,u64 offset) {
    const void *buffer=z_pointer(h,p,bytes);ZFilesystem *fs=h->runtime->files;pthread_mutex_lock(&fs->mutex);
    int fd=writable(lookup(fs,id,1));ssize_t n=fd>=0?pwrite(fd,buffer,bytes,(off_t)offset):-1;
    u32 result=n<0?(u32)-29:(u32)n;pthread_mutex_unlock(&fs->mutex);return result;
}
void Z_IMPORT__wasmfs_opfs_get_size_file(struct w2c_a *h,u64 ctx,u32 id,u64 out) {
    ZFilesystem *fs=h->runtime->files;pthread_mutex_lock(&fs->mutex);z_write64(h,out,size_of(lookup(fs,id,1)));pthread_mutex_unlock(&fs->mutex);finish(h,ctx);
}
void Z_IMPORT__wasmfs_opfs_get_size_access(struct w2c_a *h,u64 ctx,u32 id,u64 out) { Z_IMPORT__wasmfs_opfs_get_size_file(h,ctx,id,out); }
u64 Z_IMPORT__wasmfs_opfs_get_size_blob(struct w2c_a *h,u32 id) {
    ZFilesystem *fs=h->runtime->files;pthread_mutex_lock(&fs->mutex);u64 n=size_of(lookup(fs,id,1));pthread_mutex_unlock(&fs->mutex);return n;
}
void Z_IMPORT__wasmfs_opfs_set_size_access(struct w2c_a *h,u64 ctx,u32 id,u64 bytes,u64 error) {
    ZFilesystem *fs=h->runtime->files;pthread_mutex_lock(&fs->mutex);int fd=writable(lookup(fs,id,1));
    z_write32(h,error,fd<0||ftruncate(fd,(off_t)bytes)?(u32)-29:0);pthread_mutex_unlock(&fs->mutex);finish(h,ctx);
}
void Z_IMPORT__wasmfs_opfs_set_size_file(struct w2c_a *h,u64 ctx,u32 id,u64 bytes,u64 error) { Z_IMPORT__wasmfs_opfs_set_size_access(h,ctx,id,bytes,error); }
void Z_IMPORT__wasmfs_opfs_free_file(struct w2c_a *h,u32 id) {
    ZFilesystem *fs=h->runtime->files;pthread_mutex_lock(&fs->mutex);release(fs,id);pthread_mutex_unlock(&fs->mutex);
}
void Z_IMPORT__wasmfs_opfs_free_directory(struct w2c_a *h,u32 id) { Z_IMPORT__wasmfs_opfs_free_file(h,id); }
void Z_IMPORT__wasmfs_opfs_close_blob(struct w2c_a *h,u32 id) { Z_IMPORT__wasmfs_opfs_free_file(h,id); }
void Z_IMPORT__wasmfs_opfs_close_access(struct w2c_a *h,u64 ctx,u32 id,u64 error) { Z_IMPORT__wasmfs_opfs_free_file(h,id);z_write32(h,error,0);finish(h,ctx); }
void Z_IMPORT__wasmfs_opfs_flush_access(struct w2c_a *h,u64 ctx,u32 id,u64 error) {
    ZFilesystem *fs=h->runtime->files;pthread_mutex_lock(&fs->mutex);ZFile *f=lookup(fs,id,1);
    z_write32(h,error,!f||(f->write_fd>=0&&fsync(f->write_fd))?(u32)-29:0);pthread_mutex_unlock(&fs->mutex);finish(h,ctx);
}
// No Emscripten preload pack is used: the player's installation is mounted via OPFS.
u32 Z_IMPORT__wasmfs_get_num_preloaded_files(struct w2c_a *h) { (void)h;return 0; }
u32 Z_IMPORT__wasmfs_get_num_preloaded_dirs(struct w2c_a *h) { (void)h;return 0; }
u32 Z_IMPORT__wasmfs_stdin_get_char(struct w2c_a *h) { (void)h;return (u32)-1; }

typedef struct { char *name;u32 type; } Listing;
void Z_IMPORT__wasmfs_opfs_get_entries(struct w2c_a *h,u64 ctx,u32 id,u64 entries,u64 error) {
    ZFilesystem *fs=h->runtime->files;Listing *list=NULL;size_t count=0,capacity=0;int failure=0;
    pthread_mutex_lock(&fs->mutex);ZFile *dir=lookup(fs,id,2);
    if(!dir)failure=-54;
    for(int pass=0;dir&&pass<2;pass++) {
        int fd=pass?dir->write_fd:dir->read_fd;if(fd<0)continue;
        int scan=openat(fd,".",O_RDONLY|O_DIRECTORY|O_CLOEXEC);DIR *d=scan>=0?fdopendir(scan):NULL;
        if(!d){if(scan>=0)close(scan);failure=-29;break;}
        struct dirent *entry;
        while((entry=readdir(d))) {
            if(!component(entry->d_name))continue;
            struct stat st;
            if(fstatat(fd,entry->d_name,&st,AT_SYMLINK_NOFOLLOW)||(!S_ISDIR(st.st_mode)&&!S_ISREG(st.st_mode)))continue;
            bool duplicate=false;for(size_t i=0;i<count;i++)if(!strcmp(list[i].name,entry->d_name)){duplicate=true;break;}
            if(duplicate)continue;
            if(count==capacity){capacity=capacity?capacity*2:32;Listing *next=realloc(list,capacity*sizeof *list);if(!next){failure=-48;break;}list=next;}
            list[count].name=strdup(entry->d_name);list[count].type=S_ISDIR(st.st_mode)?2:1;count++;
        }
        closedir(d);if(failure)break;
    }
    pthread_mutex_unlock(&fs->mutex);
    for(size_t i=0;i<count;i++) {
        size_t bytes=strlen(list[i].name)+1;u64 p=Z_EXPORT_malloc(&h->engine,bytes);
        memcpy(z_pointer(h,p,bytes),list[i].name,bytes);Z_EXPORT__wasmfs_opfs_record_entry(&h->engine,entries,p,list[i].type);
        Z_EXPORT_free(&h->engine,p);free(list[i].name);
    }
    free(list);z_write32(h,error,(u32)failure);finish(h,ctx);
}
