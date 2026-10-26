# mechanism-verification changelog

- **0.2 (draft)** — Tested the trigger against five inline cases (2 trigger,
  1 boundary, 2 edge). The boundary case — "write a unit test for the
  parser's error handling" — fired, and should not have: "adding or
  reviewing a test" catches every ordinary unit test, and a skill that fires
  on everything gets ignored, which is the same outcome as one that never
  fires. Replaced the keyword with an intent tie-breaker: does the thing
  exist to *prevent* a class of change, or to *describe* behaviour. Only the
  former needs this.
- **0.1 (draft)** — Initial version. Trigger drafted from six recorded
  instances in this repository: unfilterable bats tags, a STRIDE control
  named without a mechanism, a setup skill certifying a hook by reading it,
  a padding probe that silently appended nothing, a skill description that
  never loaded, and a pull-request body whose bare issue numbers closed
  nothing. Step 3 comes from the fourth of those.
