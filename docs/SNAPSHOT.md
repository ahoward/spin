# spin — snapshot of shared understanding (2026-06-23)

a checkpoint of what spin is and where we are, before building the
declarative resource DSL (#7).

## what spin is

the minimalist web framework for [matz/spinel](https://github.com/matz/spinel),
spinel being matz's Ruby AOT compiler (Ruby → type inference → C → standalone
native binary; also targets WASM; instant startup, no runtime deps).

**the model:** a handler is a **logical resource you talk to**, not an HTTP
endpoint. every message collapses to **read** (give me state) or **write**
(change state). request and response are one **unified string→string bag** —
headers, query params, issue fields are just keys. the handler never sees a
socket, so it is **transport-agnostic** (HTTP, github issue, tunnel, queue)
and **host-agnostic** (laptop, container, edge/WASM, free CI compute). spinel
makes each handler a fast tiny binary, so "run a handler anywhere, triggered
by anything" is actually viable.

## proven + shipped (all verified)

- spinel compiles a web handler — 17–30KB binary, ~1.5ms cold start, CGI
  contract (ENV + stdin → stdout). `docs/spike-handler.md`
- WASM/edge path — same handler → wasm32-wasi → wasmtime. ~38-line runtime
  patch (still in scratch `/tmp/webframe-spike/`, not yet in repo — issue #2).
  `docs/spike-hosting.md`
- HTTP adapter — `bin/spin-serve` (handlers are URLs)
- github-as-substrate adapter — `bin/spin-gh-adapter` + workflow (issue is the
  request, Action is the free runtime)
- the resource-model DSL — `spin.rb`: `read(req)`/`write(req)` +
  `case resource(req)` + `reply(...)`. `docs/dsl-exploration.md`

## the road (open issues)

1. spinel stdlib reach (JSON, hashes, FFI)
2. vendor/upstream the `__wasm__` runtime patch
3. deploy story (`spin deploy` → container | wasm | edge)
4. routing mechanics (multi-param, query, headers)
5. run the github workflow live
6. naming (Fermyon Spin overlap)
7. **declarative resource DSL ← building now**
8. formalize the transport-neutral bag envelope

## #7 — the declarative resource DSL (the genius bit)

**the idea (ara's):** the authoring language is *real Ruby*, evaluated at
**build time** in a DSL context, that **codegens compilable Ruby** for
spinel. the preprocessor runs in full CRuby — unconstrained — and emits the
boring subset spinel can compile. ergonomics live in the DSL; compilability
lives in the output. "reads like a spec, compiles like C."

you write (`app.rb` — real ruby, using the spin DSL):

```ruby
resource "notes" do
  read  { |req| reply(200, "all notes (id=#{resource_id(req)})") }
  write { |req| reply(201, "wrote #{req["body"].length} bytes") }
end

resource "health" do
  read { |req| reply(200, "ok") }
end
```

`spin build app.rb` →
1. eval app.rb in a DSL context where `resource`/`read`/`write` record blocks
   into a table (this runs in CRuby, unconstrained)
2. codegen a spinel-ready handler (`read`/`write` methods with
   `case resource(req)` branches expanded from the table)
3. invoke spinel on the generated file → native (or wasm) binary

### decisions (locked)

- **extension is `.rb`, not `.spin`.** the DSL is valid ruby; editors already
  understand `.rb`. spin-ness = the DSL methods being in scope, not a weird
  extension. generated file gets a distinct name (e.g. `app.spin.rb` or
  `build/app.rb`) — kept on disk, inspectable, not hidden.
- **block contract:** `read { |req| ... }` — explicit `req` param (the string
  bag); `reply`/`resource_id`/etc. available inside.
- **build flow:** `spin build app.rb` → generated handler.rb (kept) → spinel
  → binary. transparent: you can read the generated ruby.

### the hard constraint

the *emitted* ruby must stay within spinel's compilable subset (string→string
hash, case/when on strings, methods returning hashes, bare gets). the
preprocessor is where ergonomics live; the output is the boring compilable
form. every generated shape must be verified to actually compile.
