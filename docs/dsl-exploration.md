# spin DSL exploration: beyond HTTP, toward "logical resources you talk to"

the v0 routing (`spin_get?(method, path, "/")`) sucks: it repeats
`method, path` every line, it's HTTP-method-shaped, and it treats a handler
as "code behind GET /foo" instead of as a **resource** — an addressable
logical thing you send messages to.

this doc explores cleaner directions. every option below was **probed
against real spinel** — the syntax shown compiles today unless marked
otherwise. (spinel constraints: no runtime proc-tables; homogeneous typed
structures; `case/when` on strings ✅; `Hash<string,string>` ✅; methods that
take and return a hash ✅; hash iteration ✅.)

## the reframe (the part that matters)

you said: *logical resource you can talk to · read || write · headers are
just strings · unified data format · beyond simple http / gh-actions.*

that's not "prettier routes." it's a different model:

- a handler is a **resource**, not an HTTP endpoint.
- every message is fundamentally **read** (give me state) or **write**
  (change state). HTTP GET → read; POST/PUT/PATCH/DELETE → write. a gh-issue
  comment → write. a tunnel query → read. the *transport's* verb is an
  implementation detail that collapses to one bit.
- a request is a **bag of strings** (`req["path"]`, `req["method"]`,
  `req["host"]`, `req["body"]`, any header). a response is a **bag of
  strings** (`res["status"]`, `res["body"]`, `res["content-type"]`). headers
  aren't special — they're just more keys. one unified format in and out.
- the same resource answers over HTTP, a gh-issue, a tunnel, a queue —
  because it only ever sees bags, never a socket.

this is closer to **9P / REST-as-actually-meant / the actor model** than to
Sinatra. Sinatra was the *simplicity* bar; the *model* is "talk to a
resource."

---

## Option A — the read/write resource (RECOMMENDED, compiles today)

the user writes two methods. that's the whole handler.

```ruby
# notes.rb — a resource you can talk to.
require_relative "spin"

def read(req)
  reply(200, "reading #{req["path"]}")
end

def write(req)
  reply(201, "wrote #{req["body"].length} bytes to #{req["path"]}")
end
```

`spin.rb` provides `reply(status, body)` (returns a res bag) and an appended
runner that: builds the req bag from ENV+stdin, picks read|write by verb,
emits the res bag as CGI. **verified compiling + running.**

- GET /notes → `read` → 200 "reading /notes"
- POST /notes (body "hello") → `write` → 201 "wrote 5 bytes to /notes"

why it's good: zero routing ceremony, transport-agnostic by construction,
the read||write polarity is *the* model. headers are `req["x"]`. one resource
per handler binary (which fits spin's "fast binary per handler" grain).

multi-resource routing (one binary, many paths) sits *on top*: a `resource`
helper + `case path` dispatch (Option C). but the atomic unit is read/write.

---

## Option B — sub-resources via a path-keyed case (compiles today)

when one binary serves several logical resources, dispatch on the leading
path segment, still read/write within each:

```ruby
require_relative "spin"

def read(req)
  case resource(req)            # resource() = first path segment
  when "notes"  then reply(200, "all notes")
  when "users"  then reply(200, "all users")
  else               reply(404, "no such resource")
  end
end

def write(req)
  case resource(req)
  when "notes"  then reply(201, "created a note")
  else               reply(405, "#{resource(req)} is read-only")
  end
end
```

clean, flat, compiles (case/when on strings ✅). read|write stays the spine;
the resource name is data. 405-vs-404 falls out naturally (a resource that
defines no write branch is read-only).

---

## Option C — declarative resource table, macro-expanded at BUILD time

spinel can't do a runtime proc-table. but a `spin` CLI preprocessor could
let you *write* a table and **expand it to the if/elsif or case dispatch
before handing to spinel**. you get declarative ergonomics; spinel gets
static dispatch.

you write:

```ruby
# resources.spin  — not ruby yet; spin compiles it to a handler.rb
resource "notes" do
  read  { reply(200, store_get("notes")) }
  write { reply(201, store_put("notes", req["body"])) }
end

resource "health" do
  read { reply(200, "ok") }
end
```

`spin build` macro-expands this into the Option-B ruby (a `read`/`write`
with a `case resource(req)`), then spinel-compiles that. the blocks become
case branches at build time — no runtime procs, so it compiles; but the
*authoring* surface is fully declarative.

cost: a real preprocessor (parse the `resource`/`read`/`write` forms, emit
ruby). more to build. biggest payoff. **this is the "beyond" answer** — the
authoring language isn't constrained by spinel because it's compiled to ruby
first.

---

## Option D — the bag IS the protocol (transport-neutral envelope)

formalize the unified data format as the contract, independent of any
transport. a resource is `bag -> bag`. each transport has an *adapter* that
maps its native shape to/from the bag (we already have HTTP and gh-issue
adapters — they'd just produce bags).

```
# the envelope (string->string), same over every transport:
req:
  verb    : "read" | "write"     # already collapsed by the adapter
  path    : "/notes/42"
  body    : "..."
  *       : any transport key (http header, issue field, query param)

res:
  status  : "200"
  body     : "..."
  *        : any reply key (becomes a header / comment field / etc.)
```

the handler never knows if it was reached by curl, a github issue, or a
tunnel. **this is the real unification** — Options A–C are *how you write the
resource*; D is *the spec of what flows in and out*. they compose: write an
A/B/C resource, it speaks the D envelope.

---

## recommendation

ship **A + B now** (verified, zero new tooling): read/write resources with
optional path-keyed sub-dispatch, over the **D envelope** (formalize the bag
so transports are pluggable). then build **C** (the declarative
preprocessor) as the headline authoring experience once the model proves
out — it's the thing that makes spin not just "compiles like C" but "reads
like a spec."

open question for you: is the atomic unit **one resource per binary**
(A, maximal spinel-grain, many tiny binaries) or **many resources per
binary** (B/C, one fatter binary routes internally)? both compile; it's a
deployment-grain choice.
