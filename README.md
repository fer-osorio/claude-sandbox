# claude-sandbox

Docker-based sandboxing for running Claude Code sessions with strict,
verifiable security controls: non-root execution, dropped capabilities,
network-egress allowlisting via a Squid proxy, and per-project image
profiles (crypto, systems, research, or plain web/Python).

Each session runs in an ephemeral container — nothing persists between
sessions except your project directory and the global instruction layer,
so there's no state to drift and nothing for one session to leak into the
next.

## Quickstart

```bash
docker network create --driver bridge claude-net   # once
./build.sh                                          # build all images
./start.sh ~/projects/myproject crypto              # start a session
```

`crypto` can be `base`, `crypto`, `systems`, or `research` depending on
your project — see the [user guide](docs/user_guide.md) for how to choose.

## Documentation

| Doc | Covers |
|---|---|
| [`docs/user_guide.md`](docs/user_guide.md) | Day-to-day usage: picking a profile, the session lifecycle, adding tools, troubleshooting |
| [`BUILDING.md`](BUILDING.md) | Build/run/test commands |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Image hierarchy and dependency management strategy |
| [`docs/claude_code_security_plan.md`](docs/claude_code_security_plan.md) | Threat model and security controls |
| [`docs/squid_proxy_guide.md`](docs/squid_proxy_guide.md) | Outbound network allowlisting |
| [`docs/designs/`](docs/designs/) | Design documents for individual subsystems (global layer injection, testing harness) |
| [`docs/designs/docs-as-code-workflow.md`](docs/designs/docs-as-code-workflow.md) | How this project decides what to document and where |
