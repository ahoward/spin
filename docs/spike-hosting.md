# spike findings: serverless hosting of spinel handlers

date: 2026-05-30
question: how can a spinel-compiled binary handler be hosted serverless-ly
(cloudflare, etc)? priority: zero-ops "just deploy a binary," any platform.

## the two strategies

a spinel handler emits a native Linux ELF. "serverless" splits by what the
platform will execute:

| platform | runs raw native ELF? | path |
|---|---|---|
| CF Workers (isolate) | no | requires WASM/WASI |
| CF Containers | yes | container, runs today |
| AWS Lambda | yes | custom runtime / container image |
| Google Cloud Run | yes | container |
| Fly.io | yes | container/VM |
| GitHub Actions | yes | ephemeral VM (the "free compute" angle) |

- **Strategy A (WASM/WASI):** compile to wasm32-wasi, run in isolate/edge
  runtimes (CF Workers, Fastly, wasmtime). true edge.
- **Strategy B (container):** keep the native binary, wrap with an
  HTTP→CGI shim in a container. works today on Lambda/Cloud Run/Fly/CF
  Containers, unmodified.

## what was verified

### the CGI contract is the key

the handler model proven earlier — `ENV` (request meta) + `stdin` (body) →
`stdout` (response) — is **transport- AND host-agnostic**. it delegates
networking to the host. that is precisely why it ports to WASI: WASI gives
you env + stdio but no sockets, and a CGI handler needs no sockets.

### Strategy A (WASM) — VERIFIED working

the same `handler.rb` (GET/POST/405, HTTP-shaped response), compiled to
WebAssembly and run under wasmtime:

```
spinel handler.rb -c                    # → handler.c
clang --target=wasm32-wasi \            # wasi-sdk 25
  -mllvm -wasm-enable-sjlj \            # spinel uses setjmp/longjmp
  -O2 -Ilib-wasm handler.c -lm \
  -o handler.wasm                        # → 170KB wasm

wasmtime run --env REQUEST_METHOD=GET handler.wasm    # → correct 200
printf '{...}' | wasmtime run --env REQUEST_METHOD=POST handler.wasm  # → 201
```

all methods correct. ~12ms per invocation through the full wasmtime CLI
(includes module compile each run; a pre-instantiated isolate à la CF
Workers would be sub-ms).

#### the WASI port cost: 38 lines, all in one header

spinel has no `__wasm__` target today. porting required patching only
`sp_runtime.h` platform-shim regions — **zero changes to the handler or the
compiler**:

1. platform include block: add `__wasm__` branch (no ucontext/mman/wait;
   mmap→malloc shim). mirrors the existing `_WIN32` branch.
2. libc gaps absent in wasi-sysroot: stub `malloc_trim` (no-op),
   `getppid` (return 0), `popen`/`pclose` (return null). all dead code on a
   handler's path.
3. fibers: stub the `sp_Fiber_*` functions to `sp_raise` if called. WASM
   has no native stack-switching; a CGI handler never creates a Fiber.
4. compile flag: `-mllvm -wasm-enable-sjlj` (spinel uses setjmp/longjmp for
   exceptions; wasmtime supports the exception-handling proposal).

the non-portable surface (`sp_net.c` sockets, fork, ucontext fibers) is
**isolated**, not pervasive. everything else (sp_core, sp_bigint, sp_crypto,
sp_pack, sp_strscan, stringio) is portable libc. this is the encouraging
result: a clean upstream `__wasm__` branch is ~40 lines, not a rewrite.

### Strategy B (container) — works today, no changes

the native binary built earlier (17KB, ~1.5ms cold start) drops straight
into a container or Lambda custom runtime with a thin HTTP→CGI adapter. not
yet built here, but nothing about it is uncertain — it's 1990s CGI with a
modern wrapper, and the ~1.5ms cold start means per-request fork+exec is
fine. this satisfies the stated priority (zero-ops deploy) directly.

## the answer

**yes — both paths work, and which to use depends on whether you want edge.**

- want true edge / CF Workers isolate → WASM path. verified feasible;
  needs the ~40-line `__wasm__` runtime branch upstreamed (or carried as a
  patch). a WASM module + a fetch→(env,stdin)→stdout shim = a Worker.
- want zero-ops "just deploy a binary" on Lambda/Cloud Run/Fly/CF Containers
  → container path. works today, native binary unmodified.

either way, the CGI contract is what makes a handler portable across
transports (HTTP server, GitHub issue/Action, tunnel) AND hosts (native,
container, WASM/edge). that contract is the real primitive.

## artifacts in this spike dir

- `handler.rb` — the handler source
- `handler` — native ELF (17KB)
- `handler.c` — spinel-generated C
- `handler.wasm` — wasm32-wasi module (170KB), runs under wasmtime
- `lib-wasm/` — the 38-line-patched runtime (copy; spinel/lib/ is pristine)
- `wasi-sdk-25.0-x86_64-linux/` — the toolchain (gitignore this; 100MB+)

## next forks (undecided)

- upstream the `__wasm__` branch to spinel, or carry a patch?
- the HTTP→CGI shim: write it (native + wasm variants) to make a real
  deployable unit?
- which transport to prove next (GitHub-as-substrate is the novel one)?
- the orchestration/routing layer format.
