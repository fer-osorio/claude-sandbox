# ── claude-systems
# Extends claude-base with the C++ systems development stack:
#   CMake, GCC/G++ toolchain, Google Test, Ninja, pkg-config.
#
# GTest note:
#   libgtest-dev on Debian ships source files only — no compiled libraries.
#   The libraries must be built from source, which we do at image build time
#   so that CMake projects can use find_package(GTest) without any extra setup.
#   This is a one-time cost paid during docker build, not at project build time.
#
# Build (after claude-base exists):
#   docker build --build-arg HOST_UID=$(id -u) -t claude-systems ./systems/
FROM claude-base

# ─────────────────────────────────────────────────────────────────────────────
# BUILD ARGUMENTS
# HOST_UID must be passed again — ARG values do not inherit across FROM.
# ─────────────────────────────────────────────────────────────────────────────
ARG HOST_UID=1000

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 1 — Build toolchain packages
# build-essential provides gcc, g++, make, and libc-dev.
# libgtest-dev provides the GTest source under /usr/src/googletest.
# ─────────────────────────────────────────────────────────────────────────────
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake \
    build-essential \
    libgtest-dev \
    ninja-build \
    pkg-config \
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
