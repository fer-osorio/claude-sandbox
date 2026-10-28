# CLI credential input and ergonomics

## Status

Accepted

## Context

#147 chains #133 and #134. Each of those issues called itself Case B. The
fourth item added to #134, `@name` in `creds.sh`, changes that: `start.sh`
and `creds.sh` would share the registry code, which is a new abstraction
across both. That makes the change Case C.

Two facts from the code shape the decisions:

- `creds.sh` already sources `config.sh` and `config.local.sh` for every
  command (`creds.sh:53-54`). It just skips the registry guard from
  [`0030`](0030-named-project-registry.md) §Layering, because it never reads
  the registry. Accepting `@name` therefore adds no new trust in
  `config.local.sh`. The paragraph in #134 that claims otherwise is wrong.
- [`0129`](0129-encrypted-credential-store.md) §Identity and passphrase model
  rules out holding the unwrapped identity in a variable to reuse it. So any
  loop that decrypts more than one file prompts once per file, as
  `cmd_rotate` already does.

## Decision

**1. Value sources for `creds.sh add` (#133).**
`add <project> <KEY> [--value-file <path> | --from-env <NAME>]`.
- A flag wins. With no flag, stdin is read when it is not a terminal.
  Otherwise the existing prompt (`read -rsp`) runs.
- A third positional argument is refused, and the error never echoes it. By
  the time it is refused it is already in argv and in shell history. The
  refusal exists so that the unsafe form never works, not to undo the leak.
- `--from-env` checks that `NAME` is a valid variable name and that the
  variable is set and non-empty.
- `--value-file` requires a regular, readable file.
- Whatever the source, trailing newlines are stripped (command-substitution
  semantics). A value that still contains a newline or a carriage return is
  rejected, because the store holds one `KEY=VALUE` per line. An empty value
  is rejected, as it is today.
- Adding a project's first credential prompts for nothing, so a pipe works
  without a terminal. A later `add` must decrypt the existing file, and `age`
  reads the passphrase from `/dev/tty`. When there is no `/dev/tty`, `add`
  says so instead of reporting "wrong passphrase".

**2. Shared config loading: `lib/config.sh`.** Both scripts source it. It
defines two functions:
- `load_config_layers` sources `config.sh`, snapshots the registry, sources
  `config.local.sh`, and reverts any committed name the local file redefined
  (moved unchanged from `start.sh`). It also records each name's origin,
  `config.sh` or `config.local.sh`, in `PROJECT_ORIGIN`.
- `resolve_project_name <name>` sets `RESOLVED_PATH` and `RESOLVED_PROFILE`,
  or fails with the messages that `start.sh` has today.

Each script keeps its own defaults and environment capture, because it reads
different variables. The guard becomes code that both scripts share, so the
two cannot drift apart.

**3. `@name` in `creds.sh`.** `resolve_project` accepts `@name` for every
`<project>` argument, including `migrate`'s `<new>`. `migrate`'s `<old>`
stays a literal path: a registry name points to where the project is now,
not where it was. The hash is computed over the same `realpath` that
`start.sh` uses, so the store format does not change.

**4. `./start.sh --list`.** It runs after the config layers are loaded and
before the engine check, so it works with no engine running. For each
registered name it prints the name, path, profile and origin, marks a path
that is not a directory as missing, and exits 0. A reverted local override
shows the committed values and its warning, which `load_config_layers`
already prints.

**5. `./creds.sh list --all`.** For each indexed project it prints the path
and the key names. It never prints a value. It prompts for the passphrase
once per credentialed project (see Context). A file that fails to decrypt is
reported, and the loop continues. Unlike `add`, this command only reads, so
nothing is left half-written.

**6. Argument errors.** Every argument error has three parts: what was
given, what was expected, and the command that fixes it. All three go to
stderr. `creds.sh` stops printing the whole usage text for a missing
argument and prints the one subcommand's usage line instead. An unknown
`@name` points to `./start.sh --list`.

## Consequences

- `start.sh`'s error messages move from stdout to stderr. The tests capture
  both, so nothing breaks. A caller that greps stdout for `Error:` would
  break, but none is known.
- `list --all` with N projects means N passphrase prompts. That is
  acceptable for an occasional audit command. Unwrapping once would change
  0129's invariant and would need its own issue, and the same fix would
  apply to `rotate`.
- A new top-level `lib/` directory. When a session runs on this
  repository, `lib/` sits under `/workspace` with the scripts that source it.
  The agent could already edit those scripts, so this adds no exposure.
- `creds.sh` gains the registry guard and its warning. A `config.local.sh`
  that redefines a committed name now warns on `creds.sh` runs too.

## Alternatives considered

- **Hold the identity in a variable for `list --all`.** This gives one
  prompt. It is rejected because it is exactly what 0129 rules out. If the
  prompts prove too costly, that belongs in its own issue.
- **Copy the registry code into `creds.sh`.** That is a smaller diff, but it
  is a second copy of a security guard. C-20 already exists only to catch the
  `DENIED_KEYS` copies drifting apart.
- **`--list` as `./creds.sh projects`.** The registry belongs to `start.sh`,
  and the issue names `start.sh --list`.
- **Error on a flag plus a piped stdin.** Rejected: cron, CI and editors
  often run commands with a non-tty stdin, so the error would fire for no
  reason.

## Implementation plan

Each step is one commit, referencing #133 or #134.

1. This design. `docs(design): CLI credential input and ergonomics (#147)`.
2. Extract `lib/config.sh` from `start.sh`, with no change in behaviour.
   `refactor(start)`.
3. `creds.sh` sources `lib/config.sh` and accepts `@name`, with tests through
   the stub `age` (#134).
4. `creds.sh add` value sources and the positional refusal, with tests and a
   negative control for each (#133).
5. `start.sh --list`, with tests (#134).
6. `creds.sh list --all`, with tests (#134).
7. The argument-error pass across both scripts, with tests on the fix lines
   (#134).
8. Documents: the `creds.sh` header, `BUILDING.md` and the user guide
   (including the warning about `echo | creds.sh`), the testing SDD rows, the
   `HOSTONLY_FLOOR` bump in CI, and the correction to #134's "Worth a look".
9. The closing commit (closes #133, #134, #147).
