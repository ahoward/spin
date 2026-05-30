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

## the handler contract

```ruby
# ENV carries request metadata, stdin the body, stdout the response.
# use bare `gets` (not STDIN.gets) — see docs/spike-handler.md.
method = ENV["REQUEST_METHOD"] || "GET"
puts "Status: 200"
puts "Content-Type: text/plain"
puts ""
puts "hello"
```
