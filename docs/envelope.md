# the spin envelope

the **envelope** is spin's transport-neutral contract. it is **minimal
HTTP/1.1** — both directions. a handler reads an http request on stdin and
writes an http response on stdout. a resource is `bag -> bag`, where a bag is
a flat string→string map; the http message is just that bag on the wire.

we use http itself — not CGI, not a custom key-value format — because it's
*the* standard for "a verb + a path + string headers + a body," it's
line-oriented (so spinel, which can only read stdin line-by-line, can parse
it), it's symmetric (request and response are the same shape), and keys are
preserved verbatim (no `HTTP_USER_AGENT`-style mangling). every tool already
speaks it.

a handler never knows whether it was reached by curl, a github issue, a
tunnel, or `spin call`. it only ever sees an http request and returns an http
response. that is the whole unification.

## the wire

### request (stdin)

```
READ /notes/42
user-agent: curl/8.0
content-length: 5

hello
```

- **request line**: `<VERB> <path>`. the verb may be a spin verb
  (`READ`/`WRITE`) **or** a real http method (`GET`/`POST`/`PUT`/`PATCH`/
  `DELETE`). all of them collapse to read|write — so a literal curl request
  pipes straight in, and a hand-written `READ /x` works. a trailing
  ` HTTP/1.1` is tolerated and ignored.
- **headers**: `key: value`, one per line, keys verbatim (lowercased on
  read). split on the first `: ` so values may contain colons.
- **blank line** separates headers from body.
- **body**: everything after the blank line.

### response (stdout)

```
200 OK
content-type: text/plain

all notes
```

- **status line**: `<code> <reason>`. (a CGI-style `Status: 200` is also
  accepted, for compat.)
- **headers**: any response-bag key beyond `status`/`body` — `content-type`
  and whatever else the handler set. an adapter maps these to the transport's
  native output (HTTP response headers, github comment fields, …).
- **blank line**, then the **body**.

## the bag

| request key | meaning                                       |
|-------------|-----------------------------------------------|
| `verb`      | `"read"` or `"write"` (collapsed)             |
| `path`      | resource path, e.g. `/notes/42`               |
| `body`      | request body (may be empty)                   |
| *any*       | any header, verbatim — `user-agent`, `host`, … |

| response key   | meaning                                  |
|----------------|------------------------------------------|
| `status`       | numeric status as a string, `"200"`      |
| `content-type` | the body's media type                    |
| `body`         | response body                            |
| *any*          | any reply key → a response header        |

the verb collapse: `GET`/`HEAD`/`OPTIONS`/`READ` → **read**;
`POST`/`PUT`/`PATCH`/`DELETE`/`WRITE` → **write**. a resource that declares
only `read` is read-only (write → 405); only `write` is write-only
(read → 404). both fall out of the resource table.

## why spinel can do this

spinel can read stdin only line-by-line (bare `gets`; no raw/binary read, no
NUL), and writes line-oriented text via `puts`. an http message is exactly
that: a start-line, `key: value` header lines, a blank line, a body. so the
handler parses the request with a `gets` loop + `index(": ")` + slicing — all
verified to compile — and emits the response with `puts`. no JSON parser, no
escaping, no env mangling.

## adapters

each adapter builds a request bag, hands it to `Spin::Envelope.call` (which
encodes the http request, runs the handler, decodes the http response), and
renders the response bag in its transport's shape. writing a new transport is
just that — the handler never changes.

| adapter               | transport      | verb source                          |
|-----------------------|----------------|--------------------------------------|
| `bin/spin-serve`      | HTTP           | the request method (collapsed)       |
| `bin/spin-gh-adapter` | github issue   | the ```spin block's request line     |
| `bin/spin call`       | CLI / direct   | explicit (`read`/`write`/an http verb)|

shared encoder/decoder: `lib/spin/envelope.rb`
(`encode_request`, `decode_response`, `collapse_verb`, `call`).
