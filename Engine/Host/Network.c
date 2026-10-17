#define _POSIX_C_SOURCE 200809L
#include "Host.h"
#include <arpa/inet.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

u32 Z_IMPORT__emscripten_lookup_name(struct w2c_a *h,u64 pointer) {
    const char *name=z_string(h,pointer);
    if(!*name)return 0;
    // The bundled libc's gethostname() returns this fixed browser label.
    // It denotes this machine, so resolve it locally rather than inventing
    // the browser DNS adapter's synthetic 172.29.* addresses.
    if(!strcmp(name,"emscripten"))name="localhost";
    struct in_addr address;
    if(inet_pton(AF_INET,name,&address)!=1) {
        struct addrinfo hints={.ai_family=AF_INET,.ai_socktype=SOCK_STREAM},*result=NULL;
        int error=getaddrinfo(name,NULL,&hints,&result);
        if(error||!result) {
            if(getenv("ZONE_TRACE_NETWORK"))fprintf(stderr,"[engine] IPv4 lookup failed for %s: %s\n",name,gai_strerror(error));
            if(result)freeaddrinfo(result);
            return 0;
        }
        memcpy(&address,&((struct sockaddr_in *)result->ai_addr)->sin_addr,sizeof address);
        freeaddrinfo(result);
    }
    const unsigned char *bytes=(const unsigned char *)&address.s_addr;
    // Match the pinned JS adapter's little-endian IPv4 integer, independent of
    // the native resolver's integer representation.
    u32 value=(u32)bytes[0]|((u32)bytes[1]<<8)|((u32)bytes[2]<<16)|((u32)bytes[3]<<24);
    if(getenv("ZONE_TRACE_NETWORK"))fprintf(stderr,"[engine] IPv4 lookup %s -> %u.%u.%u.%u\n",name,bytes[0],bytes[1],bytes[2],bytes[3]);
    return value;
}
