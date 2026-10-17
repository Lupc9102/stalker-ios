(module
  (tag $first (param i32))
  (tag $second)
  (func $raise (param $depth i32)
    local.get $depth
    if
      local.get $depth i32.const 1 i32.sub call $raise
    else
      i32.const 17 throw $first
    end)
  (func $unmatched
    (try (do (i32.const 16) (call $raise)) (catch $second nop)))
  (func $rethrow
    (try (do (i32.const 8) (call $raise)) (catch $first drop rethrow 0)))
  (func (export "run") (result i32)
    (try (result i32) (do (call $unmatched) (i32.const 0)) (catch $first)))
  (func (export "rethrow") (result i32)
    (try (result i32) (do (call $rethrow) (i32.const 0)) (catch $first)))
  (func (export "normal") (result i32)
    (try (result i32) (do (i32.const 42)) (catch $first drop i32.const 0)))
)
