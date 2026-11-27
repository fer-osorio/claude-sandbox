# claude-sandbox

Container-based sandboxing (Podman by default, Docker with
`ENGINE=docker`) for running Claude Code sessions with strict, verifiable
security controls: non-root execution, dropped capabilities, network-egress
allowlisting via a Squid proxy, and per-project image profiles (crypto, rust,
or plain web/Python), and combinations of them.

Each session runs in an ephemeral container — nothing persists between
sessions except your project directory and the global instruction layer,
so there's no state to drift and nothing for one session to leak into the
next.

## Quickstart

```bash
podman network create --internal claude-net        # once (or docker)
podman network create claude-egress                 # once
./build.sh                                          # build all images
./start.sh ~/projects/myproject crypto              # start a session
```

`crypto` can be `base`, `crypto`, `rust` or the `crypto-rust` combination,
depending on your project — see the [user guide](docs/user-guide.md) for how to choose.

## Documentation

| Doc | Covers |
|---|---|
| [`docs/user-guide.md`](docs/user-guide.md) | Day-to-day usage: picking a profile, the session lifecycle, storing credentials, adding tools, troubleshooting |
| [`BUILDING.md`](BUILDING.md) | Build/run/test commands |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Image hierarchy and dependency management strategy |
| [`docs/claude-code-security-plan.md`](docs/claude-code-security-plan.md) | Threat model and security controls |
| [`docs/squid-proxy-guide.md`](docs/squid-proxy-guide.md) | Outbound network allowlisting |
| [`docs/designs/`](docs/designs/) | Design documents for individual subsystems (global layer injection, testing harness) |
| [`docs/designs/docs-as-code-workflow.md`](docs/designs/docs-as-code-workflow.md) | How this project decides what to document and where |
