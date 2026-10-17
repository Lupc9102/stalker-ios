"""Restore generated call-depth accounting when an exception unwinds C frames."""
import argparse
from pathlib import Path


def patch(path):
    source = path.read_text()
    if 'ZONE_EXCEPTION_CALL_DEPTH' in source:
        print('WABT exception-depth patch already applied.'); return
    declaration = '  Write("WASM_RT_UNWIND_TARGET ", tlabel, "_unwind_target;", Newline());\n'
    save = '''  // ZONE_EXCEPTION_CALL_DEPTH: longjmp skips callee FUNC_EPILOGUEs.
  Write("#if WASM_RT_STACK_DEPTH_COUNT", Newline());
  Write("const uint32_t ", tlabel, "_saved_call_depth = wasm_rt_call_stack_depth;", Newline());
  Write("#endif", Newline());
'''
    catch_label = '''  if (try_catch_stack_.back().used) {
    Write(tlabel, "_catch:;", Newline());
  }

  return mark;
'''
    restore = '''  if (try_catch_stack_.back().used) {
    Write(tlabel, "_catch:;", Newline());
  }
  Write("#if WASM_RT_STACK_DEPTH_COUNT", Newline());
  Write("wasm_rt_call_stack_depth = ", tlabel, "_saved_call_depth;", Newline());
  Write("#endif", Newline());

  return mark;
'''
    if source.count(declaration) != 1 or source.count(catch_label) != 1:
        raise ValueError('Pinned WABT BeginTry no longer matches the reviewed patch')
    path.write_text(source.replace(declaration, declaration + save).replace(catch_label, restore))
    print('Patched exception unwinding to restore guest call depth.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    patch(parser.parse_args().source)
