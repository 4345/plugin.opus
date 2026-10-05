cmake_minimum_required(VERSION 3.16)
project(plugin_opus)

# Configure Opus options for minimal size & fixed-point math
set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "Build shared library" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build shared libs" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "Build tests" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "Build programs" FORCE)
set(OPUS_DRED OFF CACHE BOOL "Enable DRED" FORCE)
set(OPUS_OSCE OFF CACHE BOOL "Enable OSCE" FORCE)
set(OPUS_FIXED_POINT ON CACHE BOOL "Compile as fixed-point" FORCE)
# Opus 1.6.1 has a gap on aarch64 with fixed-point maths: when its NEON probe
# succeeds it sets OPUS_PRESUME_NEON, and pitch_arm.h then hard-wires
# celt_pitch_xcorr to celt_pitch_xcorr_neon - which only exists as ARM32
# assembly, so the link fails with an undefined symbol. Whether the probe
# succeeds depends on the toolchain, which is why earlier builds got away with
# it. Scalar C maths is what the working library was built from anyway, and
# 20 ms voice frames do not need the vector path.
set(OPUS_DISABLE_INTRINSICS ON CACHE BOOL "Disable intrinsics" FORCE)

# Opus 1.6.1 is not stored in this repository: tools/poluchit_opus.py downloads the
# official release into opus-1.6.1/ at the repository root.
set(OPUS_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../opus-1.6.1")
if(NOT EXISTS "${OPUS_SRC}/CMakeLists.txt")
    message(FATAL_ERROR "Opus sources not found in ${OPUS_SRC}: run 'python tools/poluchit_opus.py' from the repository root")
endif()
add_subdirectory("${OPUS_SRC}" opus)

# Create the JNI wrapper library (statically links libopus.a)
add_library(plugin_opus SHARED plugin_opus.cpp)

# Link JNI library with opus and Android logging libraries
target_link_libraries(plugin_opus opus log)
