# Skill selection and external skills — implementation plan

**Decision record:** [ADR 013](../adr/013-skill-selection-and-external-skills.md).
Each step is one commit. Steps 1 to 6 are the first PR, which ships
selection (ADR 013 decision 9). Steps 7 onward wait for a concrete
requirement.

## PR 1 — selection

1. **ADR 013 and this plan.** `docs(adr): ADR 013 — skill selection and
   external skills (#136)`.
2. **Install the EXIT trap before mount construction.** `cleanup` must
   tolerate a proxy that never started. This is a refactor with no change
   in behaviour, so the staging directory added in step 3 is removed on
   every exit path.
3. **Stage the layer.** `start.sh` copies `global-claude/` into a `mktemp -d`
   directory, mode 0700, with the skills filtered by `GLOBAL_SKILLS`, and
   mounts that directory. An unknown name aborts. The banner prints
   `Skills:`. `config.sh` carries the variable, commented out, as the
   default, and `config.local.sh.example` shows an override.
4. **Hostonly tests through a stub engine.** A stub `ENGINE` that succeeds on
   every subcommand records the `--mount` arguments and lists the staged
   directory on `run`. The tests cover:
   - unset gives every skill;
   - a subset;
   - empty gives none;
   - an unknown name aborts;
   - an overlay-only name aborts;
   - top-level files are always present;
   - the mount is `readonly`;
   - the staging directory is gone after exit.

   Negative-control each test, and raise `HOSTONLY_FLOOR`.
5. **Documents.**
   - `0003` §4.4 and §7.3 (the `start.sh` contract), and §5 (the staging
     directory as a new surface), with a changelog entry;
   - the user guide;
   - the testing SDD rows.
6. **Closing commit** for PR 1. It references #136 but does not close it.

## Later — external skills (ADR 013 decisions 3 to 7)

7. A tree-hash function, with its command documented in
   `config.local.sh.example`.
8. Manifest parsing and every abort condition in decision 4, each with a
   negative control.
9. The description-budget warning and the `External:` banner line.
10. The STRIDE entries in `0003` §5, the user guide, and the closing commit
    (closes #136).
