# Adapted from GTA V iOS Port (MIT); see Licenses/GTA-iOS-MIT.txt.
"""Add host-backed wait/notify emission to the pinned WABT 1.0.42 writer."""
from pathlib import Path

import argparse
parser=argparse.ArgumentParser()
parser.add_argument('source', type=Path)
args=parser.parse_args()
source = args.source.read_text()
if 'zone_atomic_wait32' in source:
    print('WABT atomic wait/notify patch already applied.'); raise SystemExit(0)
marker = '      case ExprType::AtomicWait:\n      case ExprType::AtomicNotify:\n'
replacement = '''      case ExprType::AtomicWait: {
        const auto inst = cast<AtomicWaitExpr>(&expr);
        const Memory* memory = module_->GetMemory(inst->memidx);
        const char* helper = inst->opcode == Opcode::MemoryAtomicWait32
                                  ? "zone_atomic_wait32" : "zone_atomic_wait64";
        Write(StackVar(2, Type::I32), " = ", helper, "(",
              ExternalInstancePtr(ModuleFieldType::Memory, memory->name), ", ");
        WriteMemoryAddress(2, memory, inst->offset);
        Write(", ", StackVar(1), ", ", StackVar(0), ");", Newline());
        DropTypes(3);
        PushType(Type::I32);
        break;
      }
      case ExprType::AtomicNotify: {
        const auto inst = cast<AtomicNotifyExpr>(&expr);
        const Memory* memory = module_->GetMemory(inst->memidx);
        Write(StackVar(1, Type::I32), " = zone_atomic_notify(",
              ExternalInstancePtr(ModuleFieldType::Memory, memory->name), ", ");
        WriteMemoryAddress(1, memory, inst->offset);
        Write(", ", StackVar(0), ");", Newline());
        DropTypes(2);
        PushType(Type::I32);
        break;
      }
'''
if source.count(marker) != 1:
    raise SystemExit('The pinned compiler source no longer matches this patch.')
args.source.write_text(source.replace(marker, replacement))
