"""Generate checked memory64-to-native GLES 3 bindings from Khronos declarations.

Only explicit pointer recipes are accepted. A new pointer-bearing API cannot
silently fall through to a cast of a guest address into a host pointer.
"""
import re
from pathlib import Path


def generate(directory, functions, header):
    declarations = {}
    for result, name, arguments in re.findall(
            r'GL_APICALL\s+([\w\s*]+?)\s*GL_APIENTRY\s+(gl\w+)\s*\((.*?)\);',
            header.read_text(), re.S):
        args = []
        for arg in arguments.split(',') if arguments.strip() != 'void' else []:
            match = re.search(r'(\w+)\s*$', arg)
            args.append((arg[:match.start()].strip(), match[1]))
        declarations[name] = (result.strip(), args)

    output = ['/* Generated from the reviewed Khronos GLES 3 declarations. */\n',
              '#include "Graphics.h"\n#include <stdlib.h>\n#include <string.h>\n']
    implemented = set()
    for imported, (result, symbol, guest_types) in functions.items():
        name = imported.replace('_emscripten_gl', 'gl').lstrip('_')
        if not name.startswith('gl'):
            continue
        if name not in declarations:
            for suffix in ('ANGLE', 'ARB', 'EXT', 'NV', 'OES', 'WEBGL'):
                if name.endswith(suffix) and name[:-len(suffix)] in declarations:
                    name = name[:-len(suffix)]
                    break
        if name not in declarations:
            continue
        native_result, args = declarations[name]
        if len(args) != len(guest_types):
            raise ValueError('GLES ABI arity changed: ' + imported)
        values = {n: f'p{i}' for i, (_, n) in enumerate(args)}
        v = lambda n: values[n]
        pointers, prelude, cleanup = {}, '', ''

        # Stable guest copies and opaque native sync handles never expose a
        # native pointer as a linear-memory address.
        special = None
        if name in ('glGetString', 'glGetStringi'):
            special = f'return z_gl_string(h,p0,{"p1" if len(args) == 2 else "UINT32_MAX"});'
        elif name == 'glFenceSync':
            special = 'return z_gl_sync_create(h,p0,p1);'
        elif name in ('glDeleteSync', 'glIsSync'):
            special = ('z_gl_sync_delete(h,p0);' if name == 'glDeleteSync' else
                       'return z_gl_sync_is(h,p0);')
        elif name == 'glGetVertexAttribPointerv':
            special = 'void *offset=NULL;glGetVertexAttribPointerv(p0,p1,&offset);z_write64(h,p2,(uintptr_t)offset);'
        elif name in ('glGetBooleanv', 'glGetFloatv', 'glGetIntegerv', 'glGetInteger64v'):
            kind = {'glGetBooleanv': 0, 'glGetFloatv': 1, 'glGetIntegerv': 2, 'glGetInteger64v': 3}[name]
            special = f'z_gl_get_state(h,p0,p1,{kind});'
        elif name == 'glBindFramebuffer':
            special = 'glBindFramebuffer(p0,z_gl_framebuffer(h,p1));'
        elif name in ('glTexStorage2D', 'glTexStorage3D'):
            tail = ',p5' if name.endswith('3D') else ''
            special = f'{name}(p0,p1,z_gl_texture_format(h,p2),p3,p4{tail});'
        elif name == 'glCompressedTexImage2D':
            special = 'z_gl_compressed_image(h,2,p0,p1,p2,p3,p4,1,p5,p6,p7);'
        elif name == 'glCompressedTexImage3D':
            special = 'z_gl_compressed_image(h,3,p0,p1,p2,p3,p4,p5,p6,p7,p8);'
        elif name == 'glCompressedTexSubImage2D':
            special = 'z_gl_compressed_sub_image(h,2,p0,p1,p2,p3,0,p4,p5,1,p6,p7,p8);'
        elif name == 'glCompressedTexSubImage3D':
            special = 'z_gl_compressed_sub_image(h,3,p0,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10);'

        if special is None:
            if name in ('glShaderSource', 'glTransformFeedbackVaryings', 'glGetUniformIndices'):
                key = 'string' if name == 'glShaderSource' else ('varyings' if name == 'glTransformFeedbackVaryings' else 'uniformNames')
                count = v('uniformCount' if name == 'glGetUniformIndices' else 'count')
                lengths = v('length') if name == 'glShaderSource' else '0'
                prelude += f'const GLchar **strings=z_gl_strings(h,{v(key)},{lengths},{count});'
                pointers[key] = 'strings'
                cleanup += 'free(strings);'
                if name == 'glShaderSource':
                    pointers['length'] = f'z_gl_optional(h,{v("length")},z_gl_count(h,{count},4))'
                elif name == 'glGetUniformIndices':
                    pointers['uniformIndices'] = f'z_pointer(h,{v("uniformIndices")},z_gl_count(h,{count},4))'
            if name.startswith(('glGen', 'glDelete')):
                for typ, key in args:
                    if '*' in typ:
                        pointers[key] = f'z_pointer(h,{v(key)},z_gl_count(h,p0,4))'
            if name.startswith('glUniform') and name.endswith(('fv', 'iv', 'uiv')):
                match = re.fullmatch(r'glUniform(Matrix)?(\d)(?:x(\d))?(?:f|i|ui)v', name)
                if match:
                    components = int(match[2]) * (int(match[3] or match[2]) if match[1] else 1)
                    pointers['value'] = f'z_pointer(h,{v("value")},z_gl_count(h,p1,{components * 4}))'
            if re.fullmatch(r'glVertexAttrib(?:I)?[1234](?:f|i|ui)v', name):
                components = int(re.search(r'[1234]', name)[0])
                pointers['v'] = f'z_pointer(h,{v("v")},{components * 4})'
            if name in ('glVertexAttribPointer', 'glVertexAttribIPointer'):
                pointers['pointer'] = f'z_gl_buffer_offset(h,GL_ARRAY_BUFFER_BINDING,{v("pointer")})'
            if name in ('glDrawElements', 'glDrawRangeElements', 'glDrawElementsInstanced'):
                pointers['indices'] = f'z_gl_buffer_offset(h,GL_ELEMENT_ARRAY_BUFFER_BINDING,{v("indices")})'
            if name in ('glBufferData', 'glBufferSubData'):
                helper = 'z_gl_optional' if name == 'glBufferData' else 'z_pointer'
                pointers['data'] = f'{helper}(h,{v("data")},z_gl_count(h,{v("size")},1))'
            if name in ('glTexImage2D', 'glTexImage3D', 'glTexSubImage2D', 'glTexSubImage3D', 'glReadPixels'):
                depth = v('depth') if 'depth' in values else '1'
                pointers['pixels'] = (f'z_gl_pixels(h,{v("pixels")},{v("width")},{v("height")},{depth},'
                                      f'{v("format")},{v("type")},{int(name == "glReadPixels")},'
                                      f'{int(name in ("glTexImage2D", "glTexImage3D"))})')
            if name.startswith('glCompressedTex'):
                pointers['data'] = f'z_gl_pixel_bytes(h,{v("data")},{v("imageSize")},false)'
            if name in ('glProgramBinary', 'glShaderBinary'):
                pointers['binary'] = f'z_pointer(h,{v("binary")},z_gl_count(h,{v("length")},1))'
                if name == 'glShaderBinary':
                    pointers['shaders'] = f'z_pointer(h,p1,z_gl_count(h,p0,4))'
            if name in ('glBindAttribLocation', 'glGetAttribLocation', 'glGetUniformLocation', 'glGetFragDataLocation', 'glGetUniformBlockIndex'):
                key = args[-1][1]
                pointers[key] = f'z_string(h,{v(key)})'
            if name in ('glDrawBuffers', 'glInvalidateFramebuffer', 'glInvalidateSubFramebuffer'):
                key = 'bufs' if name == 'glDrawBuffers' else 'attachments'
                count = v('n' if name == 'glDrawBuffers' else 'numAttachments')
                pointers[key] = f'z_pointer(h,{v(key)},z_gl_count(h,{count},4))'
            if name.startswith('glClearBuffer') and name.endswith(('fv', 'iv', 'uiv')):
                pointers['value'] = 'z_pointer(h,p2,p0==GL_COLOR?16:4)'
            if name in ('glTexParameterfv', 'glTexParameteriv', 'glSamplerParameterfv', 'glSamplerParameteriv'):
                key = args[-1][1]
                pointers[key] = f'z_pointer(h,{v(key)},4)'

            # Reflection has fixed scalar outputs, explicit capacities, or a
            # count obtained from the actual program being queried.
            if name.startswith('glGet'):
                for typ, key in args:
                    if '*' not in typ or key in pointers:
                        continue
                    count, optional = '1', False
                    if key in ('length', 'size', 'type', 'count'):
                        optional = key in ('length', 'count', 'size', 'type')
                    elif key in ('infoLog', 'source', 'name', 'binary', 'uniformBlockName'):
                        count = v('bufSize')
                    elif key == 'shaders':
                        count = f'z_gl_count(h,{v("maxCount")},4)'
                    elif name == 'glGetShaderPrecisionFormat' and key == 'range':
                        count = '2'
                    elif name == 'glGetActiveUniformsiv':
                        count = v('uniformCount')
                    elif name == 'glGetActiveUniformBlockiv':
                        count = 'z_gl_block_count(h,p0,p1,p2)'
                    elif name.startswith('glGetUniform') and key == 'params':
                        count = 'z_gl_uniform_count(h,p0,(GLint)p1)'
                    elif name.startswith('glGetVertexAttrib'):
                        count = 'p1==GL_CURRENT_VERTEX_ATTRIB?4:1'
                    elif name == 'glGetInternalformativ':
                        count = v('count')
                    elif name == 'glGetSynciv' and key == 'values':
                        count = v('count')
                    size = 1 if 'GLchar' in typ or typ.strip() == 'void *' else (8 if '64' in typ else 4)
                    # A precomputed byte expression is used for shader arrays.
                    nbytes = count if key == 'shaders' else f'z_gl_count(h,{count},{size})'
                    helper = 'z_gl_optional' if optional else 'z_pointer'
                    pointers[key] = f'{helper}(h,{v(key)},{nbytes})'

            missing = [key for typ, key in args if '*' in typ and key not in pointers]
            if missing:
                continue
            arguments = []
            for typ, key in args:
                if '*' in typ:
                    arguments.append(f'({typ})({pointers[key]})')
                elif typ == 'GLsync':
                    arguments.append(f'z_gl_sync(h,{v(key)})')
                else:
                    arguments.append(f'({typ}){v(key)}')
            call = name + '(' + ','.join(arguments) + ')'
            if result == 'void':
                special = prelude + call + ';' + cleanup
            else:
                special = prelude + f'{result} result=({result}){call};' + cleanup + 'return result;'
        declaration = ','.join(['struct w2c_a *h'] + [f'{t.strip()} p{i}' for i, t in enumerate(guest_types)])
        output.append(f'{result} {symbol}({declaration}) {{ z_gl_require(h);{special} }}\n')
        implemented.add(imported)
    (directory / 'native_gles.c').write_text(''.join(output))
    return implemented
