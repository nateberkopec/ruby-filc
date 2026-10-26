#!/usr/bin/env bash
set -euo pipefail
export PATH=/compiler/tools/bin:$PATH
cd /compiler/source
printf 'NINJAFLAGS="-j2"\nNINJARUNTIMEFLAGS="-j2"\n' > clang-build-overrides.sh
source ./setup_glibc.sh
./build_projeny_yolo.sh
./build_compiler_rt.sh
./build_yolounwind.sh
export CMAKEOPTIONS='-S ../llvm -B . -G Ninja -DLLVM_ENABLE_PROJECTS=clang -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_ASSERTIONS=ON -DLLVM_ENABLE_LLD=ON -DLLVM_TARGETS_TO_BUILD=AArch64;X86 -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_LIBPFM=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_CURL=OFF -DLLVM_ENABLE_HTTPLIB=OFF -DLLVM_STATIC_LINK_CXX_STDLIB=ON -DCMAKE_EXE_LINKER_FLAGS=-static-libgcc -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_PARALLEL_LINK_JOBS=1'
./configure_cmake_project.sh
./build_clang.sh
./build_os_include.sh
./build_yolo_glibc.sh
./build_runtime.sh
./build_user_glibc.sh
./build_cxx.sh
./build_minilute.sh
./build_sarcasm.sh
build/bin/clang --version
