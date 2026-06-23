# spin

minimalist web framework for [spinel](https://github.com/matz/spinel) (matz's
ruby→native AOT compiler). write ruby, get a ~17KB binary that cold-starts in
~1.5ms. talk to it over HTTP, a github issue, a tunnel, or the CLI — same
handler, no socket, no server runtime.

## tl;dr

```ruby
# app.rb — a resource you talk to. read || write. that's the whole model.
resource "notes" do
  read  { |req| reply(200, "all notes (id=#{resource_id(req)})") }
  write { |req| reply(201, "wrote #{req["body"].length} bytes") }
end

resource "health" do
  read { |req| reply(200, "ok") }
end
```

```bash
spin build app.rb -o notes        # ruby → spinel → ./notes (native binary)
spin call ./notes read /notes/42  # → "all notes (id=42)"
spin call ./notes write /notes <<< 'hi'
ruby bin/spin-serve ./notes       # → http://localhost:4242
```

declare only `read` → read-only (writes 405). only `write` → write-only
(reads 404). falls out of the table, no code for it.

## the envelope = minimal HTTP, both ways

a handler reads an http request on stdin, writes an http response on stdout.
no CGI, no env-mangling, no JSON parser. line-oriented text — which is all
spinel can read. keys verbatim.

```
READ /notes/42          200 OK
user-agent: curl/8.0    content-type: text/plain
                        
hello                   all notes
```

request line takes spin verbs (`READ`/`WRITE`) **or** real http
(`GET`/`POST`/...) — all collapse to read|write. so curl pipes straight in:

```bash
printf 'READ /health\n\n' | ./notes      # → 200 OK / ok
```

one encoder (`lib/spin/envelope.rb`), N transports. writing a new transport =
build a bag, `Spin::Envelope.call`. spec: [docs/envelope.md](docs/envelope.md).

## transports (same handler, different adapter)

| transport | adapter | how |
|---|---|---|
| CLI | `bin/spin call` | `spin call ./h read /path` |
| HTTP | `bin/spin-serve` | `spin-serve ./h` → URL; native ~2.5ms, wasm ~14ms |
| github issue | `bin/spin-gh-adapter` + workflow | post a ` ```spin ` block, bot replies |
| raw | the binary itself | `printf 'READ /x\n\n' \| ./h` |

### github-as-substrate (issue = request, Action = free runtime)

post in an issue/comment:

    ```spin
    READ /health
    ```

`.github/workflows/spin-handler.yml` fires, builds spinel (pinned), compiles
the handler, runs it, posts back. **proven live** — issue→binary→reply in
~2ms on a free runner. (gate is currently marker-only; real
author_association check is [#10](../../issues/10).)

## DSL → ruby → spinel (the trick)

`app.rb` is real ruby; `resource`/`read`/`write` are DSL methods. `spin build`
**evals it at build time in full CRuby** (unconstrained), then codegens a
spinel-compilable handler (`app.spin.rb`, kept + inspectable) via Prism, then
compiles that. ergonomics live in the DSL; compilability in the output.
inspect it: `spin build app.rb --gen-only`.

hand-written form (what the DSL emits) in [`spin.rb`](spin.rb) — `read`/
`write` + `case resource(req)` + `reply`. write it directly if you want.

## wasm / edge

same handler → `wasm32-wasi` → runs under wasmtime, identical envelope.
needs wasi-sdk + ~38 lines of runtime patch ([#2](../../issues/2)).
[docs/spike-hosting.md](docs/spike-hosting.md).

## status

early spike, all core pieces proven (resource model, DSL, envelope, github
transport live). built on spinel — which is days old and changes daily, so
**pin your spinel commit** (the workflow does). open work: [issues](../../issues).
docs: [PRD.md](PRD.md) · [docs/](docs/).
