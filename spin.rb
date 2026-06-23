# spin.rb — the resource prelude. require this at the top of a handler.
#
# the model: a handler is a RESOURCE you talk to, not an HTTP endpoint. every
# message collapses to READ (give me state) or WRITE (change state). the
# transport's verb — HTTP GET/POST/…, a github issue, a tunnel query — is an
# implementation detail the adapter collapses to that one bit. headers,
# query params, issue fields are not special; they're just more string keys
# in the request bag. request and response share one unified format: a
# string→string bag.
#
# a handler is therefore just:
#
#     require_relative "spin"
#
#     def read(req)
#       reply(200, "reading #{req["path"]}")
#     end
#
#     def write(req)
#       reply(201, "wrote #{req["body"].length} bytes")
#     end
#
#     spin_run
#
# that's the whole surface. no get?/post?/path-matching ceremony. for one
# binary serving several logical resources, branch on `resource(req)` inside
# read/write (see docs/dsl-exploration.md, Option B). a resource that defines
# no write branch is read-only — 405 falls out for free.
#
# constraints honored (spinel AOT): string→string Hash, case/when on strings,
# methods taking/returning a hash, bare `gets`. no runtime proc-tables.

# --- response bag builders ------------------------------------------------

# build a response bag. status + body, plus a content type (default text).
def reply(status, body)
  res = {}
  res["status"]       = "#{status}"
  res["content-type"] = "text/plain"
  res["body"]         = body
  res
end

def reply_json(status, body)
  res = {}
  res["status"]       = "#{status}"
  res["content-type"] = "application/json"
  res["body"]         = body
  res
end

def reply_html(status, body)
  res = {}
  res["status"]       = "#{status}"
  res["content-type"] = "text/html"
  res["body"]         = body
  res
end

# --- request helpers ------------------------------------------------------

# the first non-empty path segment — the logical resource name.
# "/notes/42" → "notes"; "/" → "".
def resource(req)
  parts = req["path"].split("/")
  i = 0
  while i < parts.length
    seg = parts[i]
    return seg if seg.length > 0
    i = i + 1
  end
  ""
end

# the path segment after the resource name — the resource id, if any.
# "/notes/42" → "42"; "/notes" → "".
def resource_id(req)
  parts = req["path"].split("/")
  seen = 0
  i = 0
  while i < parts.length
    seg = parts[i]
    if seg.length > 0
      seen = seen + 1
      return seg if seen == 2
    end
    i = i + 1
  end
  ""
end

# --- the envelope: minimal HTTP/1.1, both directions ----------------------
#
# the wire format IS http. the handler reads an http request on stdin and
# writes an http response on stdout. symmetric, standard, line-oriented (so
# spinel can read it), keys verbatim (no SPIN_/CGI mangling).
#
# request in:                          response out:
#   READ /notes/42                       200 OK
#   user-agent: curl/8.0                 content-type: text/plain
#   content-length: 5                    (blank)
#   (blank)                              all notes
#   hello
#
# the request line accepts BOTH spin verbs (READ/WRITE) and real http methods
# (GET/POST/PUT/PATCH/DELETE) — any of them collapses to read|write. so a
# literal curl request pipes straight in, and a hand-written `READ /x` works.

# collapse any request-line method token to spin's read|write verb.
def spin_verb(token)
  t = token || "GET"
  if t == "WRITE" || t == "write" || t == "POST" || t == "PUT" || t == "PATCH" || t == "DELETE"
    "write"
  else
    "read" # READ, GET, HEAD, OPTIONS, anything else → read
  end
end

# call `spin_run` at the bottom of a handler, after read/write are defined.
# parses the http request from stdin into the req bag, dispatches by verb,
# emits the res bag as an http response.
def spin_run
  req = {}
  req["verb"] = "read"
  req["path"] = "/"

  first = 1
  in_headers = 1
  body = ""

  while (line = gets)
    ln = line.chomp
    if first == 1
      # request line: "<METHOD> <path>"
      first = 0
      sp = ln.index(" ")
      if sp
        req["verb"] = spin_verb(ln[0, sp])
        rest = ln[(sp + 1), ln.length]
        # drop a trailing " HTTP/1.1" if a real http client sent one
        hsp = rest.index(" ")
        req["path"] = hsp ? rest[0, hsp] : rest
      else
        req["verb"] = spin_verb(ln)
      end
    elsif in_headers == 1
      if ln.length == 0
        in_headers = 0
      else
        # "key: value" — split on the FIRST ": ", key verbatim (lowercased)
        idx = ln.index(": ")
        if idx
          k = ln[0, idx]
          v = ln[(idx + 2), ln.length]
          req[k.downcase] = v
        end
      end
    else
      body = body + line
    end
  end
  req["body"] = body

  res = (req["verb"] == "write") ? write(req) : read(req)

  # http response: status line + headers + blank + body.
  puts "#{res["status"]} #{spin_status_text(res["status"])}"
  puts "content-type: #{res["content-type"]}"
  puts ""
  puts res["body"]
end

# minimal reason-phrase for the status line. unknown codes → "".
def spin_status_text(status)
  case status
  when "200" then "OK"
  when "201" then "Created"
  when "204" then "No Content"
  when "400" then "Bad Request"
  when "401" then "Unauthorized"
  when "403" then "Forbidden"
  when "404" then "Not Found"
  when "405" then "Method Not Allowed"
  when "500" then "Internal Server Error"
  else ""
  end
end
