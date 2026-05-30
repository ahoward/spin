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

## the handler — sinatra-flat, compiles to C

```ruby
require_relative "spin"

method, path = spin_request

if spin_get?(method, path, "/")
  spin_text(200, "hello from spin")

elsif spin_get?(method, path, "/hi/:name")
  spin_text(200, "hi #{spin_param("/hi/:name", path)}")

elsif spin_post?(method, path, "/echo")
  spin_text(201, "you said: #{spin_body}")

else
  spin_text(404, "not found: #{method} #{path}")
end
```

the whole routing surface is in [`spin.rb`](spin.rb): `spin_request`,
`spin_get?/post?/put?/delete?`, `spin_match?`, `spin_param`, `spin_body`,
`spin_text/json/html`. it reads like sinatra and AOT-compiles via spinel to
a ~26KB binary.

### why if/elsif and not `get("/x") { ... }`

spinel infers homogeneous, typed structures and has no runtime proc-table.
a sinatra-style block registry doesn't compile. the flat if/elsif dispatch
is the closest thing that does — same legibility, no runtime indirection.
the contract stays CGI: `ENV` (request meta) + `stdin` (body) → `stdout`
(response). use bare `gets`, not `STDIN.gets` (see docs/spike-handler.md).

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
