#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

// DDS BC1/2/3 (DXT1/3/5), including the sRGB GL formats. Decoding changes GPU
// upload format only; original archives remain untouched.
unsigned z_bc_kind(uint32_t format);
bool z_bc_srgb(uint32_t format);
bool z_bc_sizes(uint32_t format,uint32_t width,uint32_t height,uint32_t depth,size_t *input,size_t *output);
bool z_bc_decode(uint32_t format,uint32_t width,uint32_t height,uint32_t depth,
                 const void *source,size_t source_bytes,void *target,size_t target_bytes);
