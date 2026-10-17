#include "BC.h"
#include <string.h>

unsigned z_bc_kind(uint32_t format) {
    switch(format) {
    case 0x83f0:case 0x83f1:case 0x8c4c:case 0x8c4d:return 1;
    case 0x83f2:case 0x8c4e:return 2;
    case 0x83f3:case 0x8c4f:return 3;
    default:return 0;
    }
}
bool z_bc_srgb(uint32_t format) { return format>=0x8c4c&&format<=0x8c4f; }
static bool multiply(size_t a,size_t b,size_t *result) {
    if(a&&b>SIZE_MAX/a)return false;
    *result=a*b;return true;
}
bool z_bc_sizes(uint32_t format,uint32_t width,uint32_t height,uint32_t depth,size_t *input,size_t *output) {
    unsigned kind=z_bc_kind(format);size_t blocks,pixels;
    if(!kind||!width||!height||!depth)return false;
    if(!multiply(((uint64_t)width+3)/4,((uint64_t)height+3)/4,&blocks)||
       !multiply(blocks,depth,&blocks)||!multiply(blocks,kind==1?8:16,input)||
       !multiply(width,height,&pixels)||!multiply(pixels,depth,&pixels)||!multiply(pixels,4,output))return false;
    return true;
}
static uint16_t little16(const uint8_t *p) { return (uint16_t)p[0]|((uint16_t)p[1]<<8); }
static void color565(uint16_t value,uint8_t *color) {
    unsigned r=value>>11,g=(value>>5)&63,b=value&31;
    color[0]=(r<<3)|(r>>2);color[1]=(g<<2)|(g>>4);color[2]=(b<<3)|(b>>2);color[3]=255;
}
bool z_bc_decode(uint32_t format,uint32_t width,uint32_t height,uint32_t depth,
                 const void *source,size_t source_bytes,void *target,size_t target_bytes) {
    size_t input,output;
    if(!z_bc_sizes(format,width,height,depth,&input,&output)||!source||!target||source_bytes!=input||target_bytes<output)return false;
    unsigned kind=z_bc_kind(format),block_size=kind==1?8:16;
    bool transparent=format==0x83f1||format==0x8c4d;
    const uint8_t *block=source;uint8_t *destination=target;
    for(uint32_t z=0;z<depth;z++)for(uint64_t by=0;by<height;by+=4)for(uint64_t bx=0;bx<width;bx+=4,block+=block_size) {
        const uint8_t *rgb=block+(kind==1?0:8);uint16_t c0=little16(rgb),c1=little16(rgb+2);
        uint8_t colors[4][4];color565(c0,colors[0]);color565(c1,colors[1]);
        if(kind!=1||c0>c1) {
            for(unsigned c=0;c<3;c++) {
                colors[2][c]=(2*colors[0][c]+colors[1][c])/3;
                colors[3][c]=(colors[0][c]+2*colors[1][c])/3;
            }
            colors[2][3]=colors[3][3]=255;
        } else {
            for(unsigned c=0;c<3;c++){colors[2][c]=(colors[0][c]+colors[1][c])/2;colors[3][c]=0;}
            colors[2][3]=255;colors[3][3]=transparent?0:255;
        }
        uint8_t alpha[8]={0};uint64_t indices=0;
        if(kind==3) {
            alpha[0]=block[0];alpha[1]=block[1];
            if(alpha[0]>alpha[1])for(unsigned i=1;i<=6;i++)alpha[i+1]=((7-i)*alpha[0]+i*alpha[1])/7;
            else { for(unsigned i=1;i<=4;i++)alpha[i+1]=((5-i)*alpha[0]+i*alpha[1])/5;alpha[6]=0;alpha[7]=255; }
            for(unsigned i=0;i<6;i++)indices|=(uint64_t)block[2+i]<<(8*i);
        }
        for(unsigned y=0;y<4&&by+y<height;y++)for(unsigned x=0;x<4&&bx+x<width;x++) {
            unsigned i=y*4+x,selector=(rgb[4+i/4]>>((i%4)*2))&3;
            uint8_t *pixel=destination+4*(((size_t)z*height+by+y)*width+bx+x);
            memcpy(pixel,colors[selector],4);
            if(kind==2)pixel[3]=((block[i/2]>>((i%2)*4))&15)*17;
            else if(kind==3)pixel[3]=alpha[(indices>>(3*i))&7];
        }
    }
    return true;
}
