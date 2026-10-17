#include "BC.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    uint8_t pixels[512],block[32]={0};size_t input,output;
    assert(z_bc_sizes(0x83f1,5,3,2,&input,&output)&&input==32&&output==120);
    assert(!z_bc_sizes(0x83f1,UINT32_MAX,UINT32_MAX,UINT32_MAX,&input,&output));
    assert(!z_bc_sizes(0,4,4,1,&input,&output));
    // RGB565 endpoints: red and green; all four color selectors in each row.
    const uint8_t colors[]={0x00,0xf8,0xe0,0x07,0xe4,0xe4,0xe4,0xe4};memcpy(block,colors,8);
    assert(z_bc_decode(0x83f1,4,4,1,block,8,pixels,sizeof pixels));
    const uint8_t row[]={255,0,0,255,0,255,0,255,170,85,0,255,85,170,0,255};
    assert(!memcmp(pixels,row,16)&&!memcmp(pixels+48,row,16));
    // BC1's three-color mode differs between RGB and RGBA only at selector 3.
    memset(block,0,8);block[2]=0xff;block[3]=0xff;memset(block+4,0xff,4);
    assert(z_bc_decode(0x83f1,1,1,1,block,8,pixels,sizeof pixels)&&pixels[3]==0);
    assert(z_bc_decode(0x83f0,1,1,1,block,8,pixels,sizeof pixels)&&pixels[3]==255);
    // BC2 always uses four-color interpolation, even with reversed endpoints.
    memset(block,0,16);memset(block,0x87,8);block[10]=0xff;block[11]=0xff;memset(block+12,0xff,4);
    assert(z_bc_decode(0x83f2,4,4,1,block,16,pixels,sizeof pixels));
    assert(pixels[0]==170&&pixels[3]==119&&pixels[7]==136);
    // BC3's eight-alpha mode, followed by its six-alpha mode with 0/255.
    memset(block,0,16);block[0]=255;block[1]=0;block[8]=0;block[9]=0xf8;
    uint64_t selectors=0;for(unsigned i=0;i<16;i++)selectors|=(uint64_t)(i%8)<<(3*i);
    for(unsigned i=0;i<6;i++)block[2+i]=(uint8_t)(selectors>>(8*i));
    assert(z_bc_decode(0x83f3,4,4,1,block,16,pixels,sizeof pixels));
    const uint8_t a8[]={255,0,218,182,145,109,72,36};
    for(unsigned i=0;i<16;i++)assert(pixels[4*i]==255&&pixels[4*i+3]==a8[i%8]);
    block[0]=0;block[1]=255;
    assert(z_bc_decode(0x8c4f,4,4,1,block,16,pixels,sizeof pixels));
    const uint8_t a6[]={0,255,51,102,153,204,0,255};
    for(unsigned i=0;i<16;i++)assert(pixels[4*i+3]==a6[i%8]);
    // Partial edge blocks and successive depth slices must not overrun output.
    memset(block,0,32);block[0]=block[8]=0;block[1]=block[9]=0xf8;block[16]=block[24]=0x1f;
    memset(pixels,0xa5,sizeof pixels);
    assert(z_bc_decode(0x83f1,5,3,2,block,32,pixels,120));
    assert(pixels[0]==255&&pixels[60]==0&&pixels[62]==255&&pixels[120]==0xa5);
    memset(pixels,0xa5,sizeof pixels);
    assert(!z_bc_decode(0x83f1,5,3,2,block,31,pixels,sizeof pixels)&&pixels[0]==0xa5);
    assert(!z_bc_decode(0x83f1,5,3,2,block,32,pixels,119)&&pixels[0]==0xa5);
    puts("BC1/2/3: color/alpha modes, sRGB formats, partial blocks, depth slices and invalid sizes passed.");
    return 0;
}
