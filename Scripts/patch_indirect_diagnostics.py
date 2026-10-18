"""Add diagnostics at WABT's rejected indirect calls without relaxing checks."""
from pathlib import Path
import argparse


def patch(path):
    source = path.read_text()
    if 'ZONE_INDIRECT_DIAGNOSTICS' in source:
        return
    signature = '    uint32_t index) {\n  const size_t sha256size = 32;'
    call = 'func_types_eq_slowpath(&(table), ft, x))'
    if source.count(signature) != 1 or source.count(call) != 1 or source.count('    TRAP(CALL_INDIRECT);') != 2:
        raise ValueError('Indirect-call checks differ from reviewed WABT 1.0.42')
    source = source.replace(signature,'    uint32_t index, const char *caller) {\n  const size_t sha256size = 32;')
    source = source.replace(call,'func_types_eq_slowpath(&(table), ft, x, __func__))')
    source = source.replace('    TRAP(CALL_INDIRECT);',
        '    zone_indirect_failure(table, expected_type, index, caller);\n    TRAP(CALL_INDIRECT);')
    path.write_text('#include "Diagnostics.h" /* ZONE_INDIRECT_DIAGNOSTICS */\n' + source)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('header', type=Path)
    patch(parser.parse_args().header)
