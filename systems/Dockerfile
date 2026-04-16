# ── claude-systems
# Extends claude-base with the C++ systems development stack:
#   CMake, GCC/G++ toolchain, Google Test, Ninja, pkg-config,
#   static analysis (clang-tidy, cppcheck), coverage (lcov/genhtml),
#   and sanitizer runtimes (ASan, LSan, UBSan).
#
# GTest note:
#   libgtest-dev on Debian ships source files only — no compiled libraries.
#   The libraries must be built from source, which we do at image build time
#   so that CMake projects can use find_package(GTest) without any extra setup.
#   This is a one-time cost paid during docker build, not at project build time.
#
# Sanitizer note:
#   ASan, LSan, and UBSan are compiler features enabled via -fsanitize= flags.
#   They do not require separate packages when using Clang — the sanitizer
#   runtime is built into the compiler. When using GCC, the runtime ships as
#   a separate library (libasan, liblsan, libubsan) that must be installed.
#   Both compilers are included here so either toolchain works out of the box.
#   GCC 13 (the Debian bookworm default) pairs with libasan8.
#
# Coverage note:
#   lcov and genhtml are a matched pair — genhtml ships inside the lcov
#   package, so installing lcov is sufficient for both find_program calls
#   in Coverage.cmake. These tools work with GCC's --coverage instrumentation.
#   If LLVM-native coverage is ever needed, add llvm and use llvm-profdata
#   and llvm-cov instead (a separate workflow from lcov).
#
# Discovering CMake dependencies:
#   The most reliable way to find missing dependencies is to configure the
#   project inside the container and read CMake's own output:
#
#     cmake -S . -B build --fresh 2>&1 | grep -E "Could not find|found|NOT FOUND|REQUIRED"
#
#   This is authoritative — it reflects actual dependency resolution on the
#   running system rather than a text search of CMakeLists.txt. Run this
#   after any toolchain change to catch gaps early.
#
# Build (after claude-base exists):
#   docker build --build-arg HOST_UID=$(id -u) -t claude-systems ./systems/
FROM claude-base

# ─────────────────────────────────────────────────────────────────────────────
# BUILD ARGUMENTS
# HOST_UID must be passed again — ARG values do not inherit across FROM.
# ─────────────────────────────────────────────────────────────────────────────
ARG HOST_UID=1000

USER root

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 1 — Build toolchain and analysis tools
#
# build-essential: gcc, g++, make, libc-dev (GCC 13 on Debian bookworm)
# libgtest-dev:    GTest source under /usr/src/googletest (compiled in LAYER 2)
# ninja-build:     faster build backend for CMake (-GNinja)
# pkg-config:      CMake uses this to resolve .pc-file-based dependencies
#
# clang:           LLVM C/C++ compiler; required by clang-tidy and useful as
#                  an alternative compiler for sanitizer builds
# clang-tidy:      static analysis, found by ClangTidy.cmake via find_program
# cppcheck:        additional static analysis, found by Cppcheck.cmake
#
# lcov:            coverage report generator (gcov/GCC stack); genhtml is
#                  bundled inside this package — one install covers both
#                  find_program calls in Coverage.cmake
#
# libasan8:        AddressSanitizer runtime for GCC 13 (the bookworm default)
#                  Not needed for Clang — Clang embeds its own sanitizer runtime
# liblsan0:        LeakSanitizer runtime for GCC
# libubsan1:       UndefinedBehaviourSanitizer runtime for GCC and Clang
# ─────────────────────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake \
    build-essential \
    libgtest-dev \
    ninja-build \
    pkg-config \
    clang \
    clang-tidy \
    cppcheck \
    lcov \
    libasan8 \
    liblsan0 \
    libubsan1 \
    && rm -rf /var/lib/apt/lists/*

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 2 — Compile and install GTest
# cmake --install places the libraries and headers under /usr/local, which is
# on the default CMake search path. No extra CMake configuration needed in
# consuming projects.
# ─────────────────────────────────────────────────────────────────────────────
RUN cmake -S /usr/src/googletest \
          -B /usr/src/googletest/build \
          -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /usr/src/googletest/build \
    && cmake --install /usr/src/googletest/build

USER claude-agent

CMD ["claude"]
