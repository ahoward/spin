# spike findings: spinel as a web-handler substrate

date: 2026-05-30
question: can matz/spinel compile a "web-shaped handler" — the foundational
capability the whole framework idea depends on?

answer: **yes.**

## what was verified

1. **spinel builds on this machine** (gcc 13.3, make 4.3, ruby 3.3.4).
   `make deps && make` self-hosts cleanly — the compiler compiles itself to
   native binaries (spinel_analyze, spinel_codegen).

2. **the fast-start property is real.**
   - `fib(34)`: compiles in 0.33s, binary runs in 42ms.
   - a GET/POST handler: compiles in 0.34s, 17KB binary.
   - **100 cold-start invocations in 149ms → ~1.5ms per cold start**
     (including process spawn). no warm pool needed.

3. **the CGI interface is the natural handler contract.** spinel supports:
   - bare `gets` (→ sp_gets), `gets` loop to read stdin body
   - `ENV["..."]` for request metadata (method, path, headers)
   - `puts` to stdout for the response
   - string interpolation, `.chomp`, `.length`, `+`, `if/elsif/else`
   so a handler is: ENV (request meta) + stdin (body) → stdout (response).
   classic CGI — which is *exactly* the right shape for "fast binary per
   request, invokable by anything that can set env and pipe stdin."

## what does NOT work (yet)

- `STDIN.gets` (method-on-constant) — inference treats STDIN as int, emits
  0. **use bare `gets` instead.** this is the kind of stdlib-coverage gap to
  expect from a young AOT compiler; the framework should define the handler
  contract around what spinel supports today (bare gets / ENV / puts), not
  idiomatic-but-unsupported forms.
- (not yet probed: Hash literals, JSON parse/generate, sockets, regex on
  request bodies, the FFI path. spinel ships an FFI sqlite example, so FFI
  is real — untested here.)

## the working handler (handler.rb)

```ruby
method = ENV["REQUEST_METHOD"] || "GET"
path   = ENV["PATH_INFO"] || "/"

if method == "GET"
  puts "Status: 200"
  puts "Content-Type: text/plain"
  puts ""
  puts "hello from a spinel handler"
  puts "path: #{path}"
elsif method == "POST"
  body = ""
  while (line = gets)
    body = body + line
  end
  puts "Status: 201"
  puts "Content-Type: text/plain"
  puts ""
  puts "received #{body.length} bytes"
  puts "echo: #{body.chomp}"
else
  puts "Status: 405"
  puts "Content-Type: text/plain"
  puts ""
  puts "method not allowed: #{method}"
end
```

## implication for the framework

the gating unknown is cleared. a handler can be a fast, tiny, standalone
binary written in terse Ruby. the CGI contract (ENV + stdin → stdout) is:

- **transport-agnostic by construction** — HTTP server, GitHub Action,
  tunnel worker, queue consumer can all invoke it identically.
- **cold-start-free in practice** (~1.5ms), which is what makes the
  "run anywhere, including ephemeral free compute" story actually work.

next real forks (not yet decided): the orchestration/routing layer format,
which non-HTTP transport to prove first (GitHub-as-substrate is the novel
one), and how far spinel's stdlib coverage reaches for real handlers
(JSON, hashes, FFI).
```
