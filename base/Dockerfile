# ── claude-base
# The root of the image hierarchy. Every other image inherits from this one.
#
# Contains only what every project type needs regardless of domain:
#   - Shell utilities and version control (git, gh)
#   - Node.js and npm (Claude Code runtime + web toolchains)
#   - Python 3 and SQLite (used by both systems and research projects)
#   - Claude Code itself
#
# Web projects use this image directly. No separate claude-web image is needed
# because Vite and Vitest are project-level devDependencies installed via
# "npm install" inside /workspace, not global tools.
#
# Build:
#   docker build --build-arg HOST_UID=$(id -u) -t claude-base ./base/
FROM debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241

# ─────────────────────────────────────────────────────────────────────────────
# BUILD ARGUMENTS
# HOST_UID must match the UID of the user running Docker on the host so that
# bind-mounted project files are accessible without chown at runtime.
# ─────────────────────────────────────────────────────────────────────────────
ARG HOST_UID=1000

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 1 — APT PACKAGES
# python3-venv is included so per-project virtualenvs work out of the box.
# libsqlite3-dev provides headers for projects that build against SQLite.
# ─────────────────────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    gnupg \
    unzip \
    nodejs \
    npm \
    python3 \
    python3-pip \
    python3-venv \
    sqlite3 \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 2 — GitHub CLI
# Not in the default Debian repos; requires the official GitHub apt keyring.
# ─────────────────────────────────────────────────────────────────────────────
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] \
       https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 3 — Claude Code
# npm installs to /usr/local/bin/claude — on PATH for all users.
# The native Anthropic installer targets /root/.local/bin, which is not on
# the non-root user's PATH. npm is the correct method inside a Dockerfile.
# ─────────────────────────────────────────────────────────────────────────────
RUN npm install -g @anthropic-ai/claude-code

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 4 — Non-root user
# claude-agent is created with HOST_UID so bind-mounted project files have
# matching ownership. No chown at runtime, no privilege escalation needed.
# Child images that need additional group memberships (e.g. "ods" for HSM
# access) add them in their own layer after inheriting this user.
# ─────────────────────────────────────────────────────────────────────────────
RUN groupadd -r claude-agent \
    && useradd -r -g claude-agent -m -d /home/claude-agent \
               -u $HOST_UID claude-agent

WORKDIR /workspace
RUN chown claude-agent:claude-agent /workspace

# ─────────────────────────────────────────────────────────────────────────────
# LAYER 5 — Entrypoint script for global layer injection
# The script runs as claude-agent (non-root). COPY and chmod run here as root
# because USER claude-agent is set immediately after.
# ─────────────────────────────────────────────────────────────────────────────
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER claude-agent

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude"]
