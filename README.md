# spin

**the minimalist web framework for [spinel](https://github.com/matz/spinel).**

a handler is a small ruby program — `request → response` — that spinel
compiles to a fast-starting artifact (native binary OR wasm). the contract
is CGI: request metadata in `ENV`, body on `stdin`, response on `stdout`.
that makes a handler **transport-agnostic** (HTTP, github issue, tunnel,
queue) and **host-agnostic** (laptop, container, edge isolate, free CI
compute).

see [PRD.md](PRD.md) for the concept and [docs/](docs/) for spike findings.

## status: early spike. proven so far:

- spinel compiles a GET/POST/405 handler → 17KB native binary, ~1.5ms cold
  start. (`docs/spike-handler.md`)
- same handler → `wasm32-wasi`, runs under wasmtime, identical CGI contract.
  ~38 lines of runtime patches. (`docs/spike-hosting.md`)
- `bin/spin-serve` — HTTP→CGI adapter. turns a handler (native or wasm)
  into a real URL. native ~2.5ms/req; wasm ~14ms/req.

## try it

```bash
# requires spinel on PATH (https://github.com/matz/spinel)
spinel handler.rb              # → ./handler (native)
ruby bin/spin-serve ./handler  # → http://localhost:4242
curl localhost:4242/hello
curl -X POST -d 'hi' localhost:4242/submit

# wasm path (requires wasi-sdk + wasmtime; see docs/spike-hosting.md)
ruby bin/spin-serve --wasm ./handler.wasm
```

## the declarative resource DSL — reads like a spec, compiles like C

write an app as a table of resources. it's **real ruby** — `resource`/`read`/
`write` are DSL methods — but it is not compiled directly. `spin build`
evaluates it at build time in full CRuby (unconstrained), codegens a
spinel-compilable handler, and compiles that.

```ruby
# examples/notes.rb
resource "notes" do
  read  { |req| reply(200, "all notes (id=#{resource_id(req)})") }
  write { |req| reply(201, "wrote #{req["body"].length} bytes to notes") }
end

resource "health" do
  read { |req| reply(200, "ok") }
end

resource "echo" do
  write { |req| reply(200, req["body"]) }
end
```

```bash
spin build examples/notes.rb -o notes   # DSL → notes.spin.rb → spinel → ./notes
spin build examples/notes.rb --gen-only # stop after codegen; inspect the .rb
```

a resource declaring only `read` is **read-only** (writes 405); only `write`
is **write-only** (reads 404). both fall out of the table — no code for it.

**why this is the good part.** the authoring language stops being constrained
by what spinel compiles, because it's compiled to ruby *first*. the
preprocessor (`lib/spin/dsl.rb` + `lib/spin/codegen.rb`) records the
resource/read/write blocks, extracts each block body via Prism, and splices
it into a `case resource(req)` dispatch — the boring compilable form. you can
read the generated `*.spin.rb`; it's kept on disk, not hidden.

## the hand-written form (what the DSL compiles to)

under the DSL is the plain resource model — you can write it directly when
you don't want the preprocessor. a handler is a **resource you talk to**, not
an HTTP endpoint. every message collapses to **read** (give me state) or
**write** (change state). you write those two methods; the framework does the
rest.

```ruby
require_relative "spin"

def read(req)
  case resource(req)
  when "notes"  then reply(200, "all notes (id=#{resource_id(req)})")
  when "health" then reply(200, "ok")
  else               reply(404, "no such resource: #{req["path"]}")
  end
end

def write(req)
  case resource(req)
  when "notes"  then reply(201, "created a note (#{req["body"].length} bytes)")
  else               reply(405, "#{resource(req)} is read-only")
  end
end

spin_run
```

- **read || write** is the whole verb model. HTTP GET → `read`; POST/PUT/
  PATCH/DELETE → `write`; a github issue → `write`; a tunnel query → `read`.
  the transport's native verb is collapsed to that one bit by the adapter.
- **the request and response are one unified format** — a string→string bag.
  `req["path"]`, `req["method"]`, `req["host"]`, `req["body"]`, any header:
  just keys. `reply(status, body)` builds the response bag. headers aren't
  special.
- a resource with **no write branch is read-only** — the 405 falls out for
  free.
- **one binary, many resources** via `case resource(req)`; or one resource
  per binary (spin's natural grain). both compile.

surface in [`spin.rb`](spin.rb): `read`/`write` (yours) + `reply`,
`reply_json`, `reply_html`, `resource`, `resource_id`, `spin_run`.
AOT-compiles via spinel to a ~30KB binary. see
[docs/dsl-exploration.md](docs/dsl-exploration.md) for the full design space
(incl. a declarative `resource "notes" do … end` preprocessor, future).

### why a resource model, not `get("/x") { ... }`

two reasons. (1) spinel has no runtime proc-table — a sinatra-style block
registry doesn't compile. (2) more importantly, "logical resource you talk
to · read||write · headers are just strings · one data format" is a better
model than HTTP-method-shaped routing: it's transport-agnostic by
construction. the contract stays CGI under the hood: `ENV` + `stdin` →
`stdout`. use bare `gets`, not `STDIN.gets` (see docs/spike-handler.md).

## github-as-substrate transport

a GitHub issue can be the request; a workflow is the ephemeral runtime
(free compute). same handler, different adapter.

put this in an issue or comment:

```
```spin
POST /echo

{"hello":"from a github issue"}
```
```

`.github/workflows/spin-handler.yml` fires, compiles the handler, runs your
request via `bin/spin-gh-adapter`, and posts the response back as a comment.
gated to collaborators so it isn't a free-compute faucet.

verified locally (adapter logic); the workflow itself needs a pushed repo
with Actions enabled to run live.
