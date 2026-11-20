# ── claude-rust
# Extends claude-base with a pinned Rust toolchain: rustc, cargo, clippy,
# rustfmt, and the C toolchain rustc links with.
#
# Installed with rustup, not from Debian: bookworm ships rustc 1.63, which
# predates the sparse registry protocol and edition 2024, so much of
# crates.io no longer builds with it.
#
# Supply chain:
#   - rustup-init is fetched by exact version and checked against a pinned
#     SHA-256 before it runs. A mismatch fails the build.
#   - The toolchain is pinned by exact version. rustup checks every component
#     against the SHA-256 in that release's channel manifest, which it fetches
#     over TLS from static.rust-lang.org. It does not verify a signature, so
#     TLS to that host is the trust root for the toolchain itself.
#   - Versions and hashes match rust-lang/docker-rust, stable/bookworm/slim,
#     at commit 3f4c9cd699d3671ee657c75b5e592f6eb0b93824. To update, take
#     both from a newer commit there.
#
# Ownership:
#   - RUSTUP_HOME and the tool binaries are root-owned. claude-agent cannot
#     install, replace or remove a toolchain, so a session never needs
#     static.rust-lang.org, and the Squid allowlist does not include it.
#   - CARGO_HOME points into claude-agent's home, where cargo writes its
#     registry index and crate cache. The rustup proxies in
#     /usr/local/cargo/bin work wherever CARGO_HOME points.
#
# Network at session time: crate fetches go through Squid to index.crates.io
# (sparse index) and static.crates.io (crate files). See
# docs/claude-code-security-plan-changelog.md, Change 29.
#
# Build (after claude-base exists):
#   ./build.sh rust
#
# Follows the profile contract (docs/adr/014-the-profile-contract.md), so it
# can also be built on another profile's image: build.sh passes the parent as
# PARENT_IMAGE. The default serves a standalone build.
ARG PARENT_IMAGE=claude-base
FROM ${PARENT_IMAGE}

# ─────────────────────────────────────────────────────────────────────────────
# BUILD ARGUMENTS
# HOST_UID must be passed again — ARG values do not inherit across FROM.
# ─────────────────────────────────────────────────────────────────────────────
ARG HOST_UID=1000
ARG RUSTUP_VERSION=1.29.3
ARG RUST_VERSION=1.99.1

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 1 — C toolchain
# rustc invokes cc as its linker, and build scripts of crates with C parts
# need it as well. Neither is in claude-base.
# ─────────────────────────────────────────────────────────────────────────────
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 2 — rustup and the pinned toolchain
# CARGO_HOME is set for this RUN only, so the proxies land in
# /usr/local/cargo/bin. The session's CARGO_HOME is set in LAYER 3.
# ─────────────────────────────────────────────────────────────────────────────
ENV RUSTUP_HOME=/usr/local/rustup

# No SHELL override: it would persist into the next combination member. The
# one pipe below ends in sha256sum, whose status is the pipeline's.
RUN arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) rustArch=x86_64-unknown-linux-gnu; \
               rustupSha256=b1c8cb14e30889e7e2999e6b69e62d9e9b9ffc0f4df8180564d306d9680e6c55 ;; \
        arm64) rustArch=aarch64-unknown-linux-gnu; \
               rustupSha256=9f608c142e0e38a78957d0661ba1dfaf0b6fb37184cfaa4b9a0aa57af6184282 ;; \
        *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac \
    && curl -fsSL --proto '=https' --tlsv1.2 -o /tmp/rustup-init \
       "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/${rustArch}/rustup-init" \
    && echo "${rustupSha256}  /tmp/rustup-init" | sha256sum -c - \
    && chmod +x /tmp/rustup-init \
    && CARGO_HOME=/usr/local/cargo /tmp/rustup-init -y --no-modify-path \
       --profile minimal --component clippy,rustfmt \
       --default-toolchain "${RUST_VERSION}" --default-host "${rustArch}" \
    && rm /tmp/rustup-init \
    && /usr/local/cargo/bin/rustc --version \
    && /usr/local/cargo/bin/cargo --version

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 3 — Session environment
# ─────────────────────────────────────────────────────────────────────────────
ENV CARGO_HOME=/home/claude-agent/.cargo
ENV PATH=/usr/local/cargo/bin:${PATH}

USER claude-agent
