#!/bin/bash
# Fix the ownership mismatch between the bind-mounted host directory
# and the claude-agent user inside the container, then drop privileges.
chown -R claude-agent:claude-agent /workspace
exec su -s /bin/bash claude-agent -c "$(printf '%q ' "$@")"
