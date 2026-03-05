#!/usr/bin/env bash
# Usage: start-claude [project_directory]
# Before running this, check if the claude-net has been created. If not, create if using
# docker network create --driver bridge claude-net

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(realpath "$PROJECT_DIR")"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "Error: '$PROJECT_DIR' is not a directory."
  exit 1
fi

echo "Starting Claude Code sandbox for: $PROJECT_DIR"
echo "Network: Anthropic API + package registries only"
echo "Filesystem: $PROJECT_DIR (read/write), host is otherwise inaccessible"
echo ""

# ── --rm: delete the container automatically when it exits.
# Without this, stopped containers accumulate on disk. Since you want
# ephemeral, stateless sessions, always use --rm for Claude Code.
#
# ── -it: two flags combined.
# -i (interactive): keep stdin open so you can type into Claude Code.
# -t (tty): allocate a terminal so the output is formatted properly.
# Nearly always used together for interactive programs.
#
# ── --name: give the container a human-readable name for this session.
# Without it, Docker assigns a random name like "quirky_hopper".
#
# ── --mount: this is how your project files become visible inside.
# type=bind: a bind mount (mirror a host directory into the container).
# source: the absolute path on your Fedora machine.
# target: where it appears inside the container's filesystem.
# The container sees /workspace; it is physically ~/projects/myproject on your disk.
#
# ── Network isolation ─────────────────────────────────────────────
# --network claude-net: drop ALL capabilities, then restore only what's needed
#
# ── --memory and --cpus: resource caps. The container cannot consume more
# than 2 GB of RAM or 2 CPU cores regardless of what runs inside it.
#
#── --security-opt=no-new-privileges: a kernel-level restriction that prevents
# any process inside the container from using setuid tricks to gain
# more privileges than it started with.
#
# ── --cap-drop=ALL: drop every Linux capability from the container.
# Capabilities are fine-grained kernel permissions (e.g. CAP_NET_RAW for
# raw sockets, CAP_SYS_ADMIN for mounting filesystems). Dropping all of them
# means even a root process inside the container can't do much damage.
#
# ── claude-sandbox: the final argument is the IMAGE NAME to run.
# This is what you built with `docker build -t claude-sandbox`.
docker run \
  --rm \
  -it \
  --name "claude-$(basename "$PROJECT_DIR")-$(date +%s)" \
  --mount type=bind,source="$PROJECT_DIR",target=/workspace \
  --network claude-net \
  --memory="2g" \
  --cpus="2" \
  --security-opt=no-new-privileges \
  --cap-drop=ALL \
  claude-sandbox
