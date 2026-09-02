# Networked / distributed system framing

Loaded when a system (or part of one — see the hybrid case in the
router) fetches from, or authenticates against, something outside local
disk/memory. The local template's assumptions break down here in five
specific ways; each gets its own vocabulary below instead of being
folded into "it makes a request."

## The template

> `<client>` resolves `<endpoint>` via `<addressing mechanism>` and
> sends `<request representation>` over `<transport/protocol>`,
> presenting `<credential>` to authenticate (`<AuthN mechanism>`) and be
> authorized (`<AuthZ policy>`), with the channel protected by
> `<trust mechanism>`. The `<server/process>` parses the request, does
> `<processing>`, and returns `<response representation>` serialized as
> `<wire format>`. On failure: `<timeout/retry/idempotency behavior>`.

You won't fill in every slot every time — see "How much to include"
below. Treat the five concepts as the checklist to run against, not a
mandatory template to complete in full.

## The five concepts, and why each is distinct

**1. Transport and addressing** — how the target is located and how
bytes actually move. Not "it connects to the server," but: resolved via
DNS or a service registry, spoken over TCP/HTTP/2/QUIC/gRPC. This is
the direct extension of "fetching" — the local template has no
addressing step because the input is already at a known path; a network
call has to find its target before it can read anything.

**2. Authentication vs. authorization** — two different questions,
routinely collapsed into one. AuthN answers *who is calling* (a bearer
token, a client cert, a signed request). AuthZ answers *what that caller
is allowed to do*, evaluated separately (a scope, a role, an ACL entry).
A request can authenticate successfully and still be denied — if the
explanation doesn't distinguish the two, that failure mode becomes
inexplicable.

**3. Trust boundary in transit** — orthogonal to both of the above. TLS
(or mTLS) answers whether the channel itself can be read or altered by
something in the middle, independent of who the endpoints are or what
they're allowed to do. Local reads have no equivalent concept — the
data never leaves a boundary you already trust.

**4. Failure semantics** — the biggest gap versus local framing. A local
`read()` succeeds or errors cleanly and atomically. A network call can
time out with the request already applied server-side, fail on the
response leg after the request succeeded, or succeed later than the
caller gave up waiting. This is why retries, timeouts, and — critically
— **idempotency** (can this safely be sent twice?) belong in the
explanation whenever the system does anything non-trivial on failure.
Don't describe a network call as if it has the same success/fail
binary as a file read.

**5. Wire format versioning** — on disk, the producer and consumer are
usually the same build. Over a network, client and server deploy
independently, so the serialized format has to tolerate one side
changing before the other does (additive fields, version headers,
schema negotiation). Worth naming explicitly when the explanation
involves an API contract, less so for a one-off internal call.

## Secondary concepts (mention only if relevant)

- **Statefulness across calls** — HTTP is stateless by design; anything
  that behaves statefully (a session cookie, a bearer token with a
  lifetime, a WebSocket) is doing so via an explicit mechanism layered
  on top, not for free.
- **Caching / staleness** — is data fetched fresh every call, or served
  from a cache with an invalidation policy? Only worth raising if the
  explanation's correctness depends on freshness.

## How much to include

Not every networked explanation needs all five. A simple internal call
within an already-trusted boundary may not need AuthZ or transport
security spelled out. Judge by what's load-bearing for the specific
question being asked — the same discipline the local template applies
to data structures and algorithms: name the concept precisely when it
matters, don't pad the explanation with irrelevant boilerplate.

## Example

Instead of: "Git talks to GitHub to push your code, and it needs your
login to do that."

Prefer: "`git push` resolves the remote's hostname via DNS, opens an
HTTPS connection, and hands the request to a credential helper — on
Windows, `git-credential-manager.exe` — which supplies a personal
access token as a bearer credential. GitHub authenticates the token
(AuthN) and separately checks it's scoped for `repo` write access on
that specific repository (AuthZ). The connection itself is TLS-protected
independent of the token check. If the push is rejected — expired
token, wrong scope, network drop mid-request — git surfaces a non-zero
exit and the specific HTTP status rather than silently retrying,
because a push is not always safe to blindly resend."

## Notes

- Pairs with the router `SKILL.md`'s local framing whenever a system is
  hybrid — describe the local phase in that vocabulary, the networked
  phase in this one, and call out the handoff between them.
- Pairs with the "Technical Explanation Structure" skill the same way
  the router does, for the overall shape of the explanation.
