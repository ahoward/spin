# Product Requirements Document: spin

**the minimalist web framework for [spinel](https://github.com/matz/spinel).**

## 1. Problem

Web frameworks optimize for one shape of deployment (a long-running server)
and one language ergonomics tradeoff. Two frustrations motivate spin:

1. **runtime weight & cold start.** most frameworks assume a warm,
   long-lived process. that makes the interesting deployment targets —
   ephemeral compute, edge isolates, per-request spawn, free CI compute —
   awkward or impossible. you pay for a warm pool to hide cold starts.

2. **the language tradeoff.** the languages with terse, human-friendly
   handler code (ruby, python) are slow to start and not typed; the fast,
   typed ones (go, rust, typescript) are verbose. you want ruby's terseness
   *and* native speed *and* access to the whole typed C ecosystem.

spinel resolves the language tradeoff: it AOT-compiles ruby to a standalone
native binary (and, as this spike proved, to WASM), with whole-program type
inference and FFI to any C library. spin is the **web framework that turns a
spinel-compiled handler into something you can trigger from anywhere and
host anywhere.**

## 2. The Core Idea

A **handler** is a small program: `request → response`. spin's handler
contract is **CGI**:

- request metadata arrives in **`ENV`** (`REQUEST_METHOD`, `PATH_INFO`,
  headers as `HTTP_*`).
- the request body arrives on **`stdin`**.
- the response (status, headers, body) is written to **`stdout`**.

spinel compiles each handler to a fast-starting artifact (~1.5ms native
cold start; ~17KB binary). because the contract is CGI, the handler is
**both transport-agnostic and host-agnostic** — it delegates networking to
whatever invokes it.

That single property is the whole framework. A handler can be:

- **triggered by** an HTTP server, a GitHub issue/comment, a tunnel
  (ngrok/cloudflare) egress queue, a message queue, a cron — anything that
  can set env vars and pipe stdin.
- **hosted on** a laptop, a cloud VM, a container (Lambda/Cloud Run/Fly/CF
  Containers), an edge isolate (CF Workers via WASM), or ephemeral free
  compute (GitHub Actions).

spin decouples *what a handler does* from *how it's triggered* and *where it
runs*. spinel makes each handler cheap enough that "spin one up per request,
anywhere" is actually viable.

## 3. What's Proven (spike, 2026-05-30)

Both findings docs are in `docs/`. Summary:

- **spinel compiles a web-shaped handler.** GET/POST/405 branching, reading
  `ENV` + `stdin`, emitting an HTTP-shaped response. compiles in 0.34s →
  17KB native binary. (`docs/spike-handler.md`)
- **cold start is ~1.5ms** per invocation including process spawn. no warm
  pool needed — this is what makes the ephemeral-everywhere story real.
- **the WASM/edge path works.** same handler → `wasm32-wasi` → runs under
  wasmtime with the identical CGI contract. the spinel runtime needed only
  ~38 lines of platform-shim patches (fibers/popen/getppid stubbed — all
  dead code on a handler's path; networking delegated to the host).
  (`docs/spike-hosting.md`)
- **the gating constraint:** spinel's stdlib coverage is partial today
  (e.g. `STDIN.gets` fails; bare `gets` works). spin's handler contract is
  defined around what spinel supports *now*.

## 4. Target Users

- **primary:** developers who want ruby-terse handlers with native speed,
  deployed to unconventional targets (edge, ephemeral, free CI compute,
  laptop-behind-a-tunnel) without a heavy framework or a warm pool.
- **secondary:** people who want one handler definition that can be invoked
  by genuinely different triggers (HTTP, a GitHub issue, a queue) without
  rewriting it per transport.
- **non-users (v1):** teams wanting a batteries-included MVC framework,
  ORM, asset pipeline, sessions. spin is deliberately minimal.

## 5. Goals

- a handler is the unit: `request → response`, CGI contract, compiled by
  spinel to a fast artifact (native or wasm).
- transport-agnostic: the same handler runs behind any trigger.
- host-agnostic: native binary (container/VM/laptop) OR wasm (edge isolate).
- zero-ops deploy as the headline DX: write handler, `spin` it, get a URL.
- an orchestration/routing layer legible to humans AND machines, avoiding
  verbose-typed-language ceremony.

## 6. Non-Goals (v1)

- a full MVC stack, ORM, templating, sessions, asset pipeline.
- hiding spinel — spin assumes spinel and tracks its capabilities.
- supporting handler code spinel can't compile yet (the contract follows
  spinel's real coverage, not idiomatic ruby).
- auto-scaling / multi-region orchestration (that's the host platform's
  job; spin produces the artifact + adapter).

## 7. Success Metrics

| metric | target | status |
|---|---|---|
| handler compile time | < 1s | ✅ 0.34s |
| native cold start (incl spawn) | < 5ms | ✅ ~1.5ms |
| binary size (trivial handler) | < 100KB | ✅ 17KB |
| same handler runs native AND wasm | yes | ✅ verified |
| HTTP server → handler round-trip | works | ⬜ shim TBD |
| GitHub-issue → handler → result | works | ⬜ TBD |

## 8. Architecture (sketch)

```
            handler.rb  (ruby, CGI contract: ENV + stdin -> stdout)
                |
                | spinel
        ________|________
       |                 |
   native ELF        wasm32-wasi
       |                 |
   [adapters: turn a transport's request into ENV+stdin, response from stdout]
       |                 |
   HTTP server      CF Worker
   container        (fetch -> wasi)
   GH Action
   tunnel worker
```

The **adapter** is the only moving part per transport/host: it maps an
incoming request to `(ENV, stdin)`, invokes the artifact, and maps `stdout`
back to the transport's response. Everything else is the handler, unchanged.

## 9. Roadmap

1. **the HTTP→CGI shim (next).** a tiny server that accepts HTTP, sets
   `ENV`/`stdin`, spawns the handler binary (or instantiates the wasm),
   returns the response. makes a handler a real URL. native + wasm variants.
2. **GitHub-as-substrate transport (the novel one).** a GitHub issue or
   comment as the request; a workflow as the ephemeral runtime; the result
   posted back. proves "trigger from a place that isn't HTTP, run on free
   compute."
3. **the orchestration/routing layer.** how multiple handlers + routes are
   described — a manifest, a dir convention, or a tiny DSL — legible to
   humans and machines. (open: format undecided.)
4. **upstream the `__wasm__` runtime branch** to spinel, or carry it as a
   patch in spin.
5. **the deploy story.** `spin deploy` → container image or wasm module +
   adapter, pushed to a chosen host (Fly/Cloud Run/Lambda/CF).

## 10. Open Questions

- routing/orchestration format: manifest vs dir-convention vs DSL?
- how much of spinel's stdlib does a *real* handler need (JSON, hashes,
  FFI), and where are the edges? (FFI is real — spinel ships a sqlite FFI
  example — but untested for handlers.)
- the `__wasm__` branch: upstream to spinel, or vendor a patch?
- naming: `spin` overlaps with Fermyon Spin (also WASM serverless). fine for
  a personal/spinel-scoped tool; revisit if promoted broadly.
- multi-handler composition: does spin route to N handlers (one process per
  route) or compile a dispatcher? per-request-binary keeps cold start low
  but multiplies artifacts.
