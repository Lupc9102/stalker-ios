cmake_minimum_required(VERSION 3.23)
project(ZoneEngineProbe LANGUAGES C)
set(CMAKE_C_STANDARD 11)
set(WABT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../Tools/wabt" CACHE PATH "Pinned patched WABT checkout")
set(ZONE_GENERATED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/Generated" CACHE PATH "wasm2c output directory")
find_package(Threads REQUIRED)
file(GLOB ENGINE_C CONFIGURE_DEPENDS "${ZONE_GENERATED_DIR}/xray_*.c")
if(NOT ENGINE_C)
  message(FATAL_ERROR "Generate the engine first with Scripts/prepare_engine.py")
endif()
add_library(xray_aot STATIC ${ENGINE_C} Host/Atomics.c
  "${WABT_ROOT}/wasm2c/wasm-rt-impl.c"
  "${WABT_ROOT}/wasm2c/wasm-rt-mem-impl.c"
  "${WABT_ROOT}/wasm2c/wasm-rt-exceptions-impl.c")
target_include_directories(xray_aot PUBLIC "${ZONE_GENERATED_DIR}" "${WABT_ROOT}/wasm2c" "${WABT_ROOT}/third_party/simde" Host)
target_compile_definitions(xray_aot PUBLIC WASM_RT_MEMCHECK_BOUNDS_CHECK=1 WASM_RT_SKIP_SIGNAL_RECOVERY=1)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
  target_compile_options(xray_aot PRIVATE -O0 -Werror=incompatible-pointer-types -Werror=implicit-function-declaration
    -include "${CMAKE_CURRENT_SOURCE_DIR}/Host/NativeRuntime.h")
endif()
target_link_libraries(xray_aot PUBLIC Threads::Threads m)
add_executable(zone_atomics_test ../Tests/atomics_test.c Host/Atomics.c
  "${WABT_ROOT}/wasm2c/wasm-rt-impl.c" "${WABT_ROOT}/wasm2c/wasm-rt-mem-impl.c")
target_include_directories(zone_atomics_test PRIVATE "${WABT_ROOT}/wasm2c" "${WABT_ROOT}/third_party/simde" Host)
target_compile_definitions(zone_atomics_test PRIVATE WASM_RT_MEMCHECK_BOUNDS_CHECK=1 WASM_RT_SKIP_SIGNAL_RECOVERY=1)
target_link_libraries(zone_atomics_test PRIVATE Threads::Threads m)
enable_testing()
add_test(NAME wasm_atomics COMMAND zone_atomics_test)
if(EXISTS "${ZONE_GENERATED_DIR}/cpu_probe.c")
  add_executable(zone_cpu_probe "${ZONE_GENERATED_DIR}/cpu_probe.c")
  target_link_libraries(zone_cpu_probe PRIVATE xray_aot)
endif()
# This archive still has unresolved browser imports. It is intentionally NOT
# linked into the iOS target until a real host exists for every required call.
