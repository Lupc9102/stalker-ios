(module
  (type $void (func))
  (func $wrong (param i32))
  (table 1 funcref)
  (elem (i32.const 0) $wrong)
  (func (export "badtype") i32.const 0 call_indirect (type $void))
  (func (export "badindex") i32.const 9 call_indirect (type $void))
)
