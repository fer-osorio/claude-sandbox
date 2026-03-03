# ── Every Dockerfile must start with FROM.
# It declares the base image — the starting filesystem your image builds on.
# "ubuntu:24.04" means: fetch the official Ubuntu image, version 24.04 (Noble Numbat).
# This is downloaded from Docker Hub (hub.docker.com) the first time you use it,
# then cached locally. Your host OS is completely irrelevant to this choice.
FROM ubuntu:24.04

# ── RUN executes a shell command during the BUILD phase (not at runtime).
# The result is baked into the image as a new filesystem layer.
# Best practice: chain related commands with && and clean up in the same layer
# (rm -rf /var/lib/apt/lists/*) so the cache files don't bloat the image.
RUN apt-get update && apt-get install -y \
    curl git nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# ── Another RUN: npm installs to /usr/local/bin/claude — always on PATH, no ambiguity
# This runs at build time, so Claude Code is baked into the image.
# You don't install it every time you start a container — it's already there.
RUN npm install -g @anthropic-ai/claude-code

# ── RUN can also run any shell logic — here, creating a non-root user and group.
# groupadd creates a group called "claude-agent".
# useradd creates a user with: -r (system user), -g (group), -m (create home),
#   -d (home directory path).
RUN groupadd -r claude-agent && \
    useradd -r -g claude-agent -m -d /home/claude-agent claude-agent

# ── WORKDIR sets the working directory for all subsequent instructions
# and for the process that runs when the container starts.
# If the directory doesn't exist, Docker creates it.
WORKDIR /workspace

# ── RUN again: give ownership of /workspace to claude-agent.
# This matters because WORKDIR creates the directory as root by default.
RUN chown claude-agent:claude-agent /workspace

# ── USER switches the active user for all subsequent instructions and
# for the container's default process at runtime.
# After this line, nothing in the build or runtime runs as root.
USER claude-agent

# ── CMD defines the default command run when the container starts.
# This is what executes when you run `docker run claude-sandbox` with no
# extra arguments. Here it launches Claude Code directly.
CMD ["claude"]
