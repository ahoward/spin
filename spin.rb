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

# --- the runner -----------------------------------------------------------
# call `spin_run` at the very bottom of a handler, after read/write are
# defined. builds the req bag from the CGI environment (ENV + stdin),
# collapses the verb to read|write, dispatches, and emits the res bag.

def spin_run
  req = {}
  req["method"] = ENV["REQUEST_METHOD"] || "GET"
  req["path"]   = ENV["PATH_INFO"] || "/"
  req["query"]  = ENV["QUERY_STRING"] || ""
  req["host"]   = ENV["HTTP_HOST"] || ""

  body = ""
  while (line = gets)
    body = body + line
  end
  req["body"] = body

  # the verb collapse: anything that mutates is a write; everything else
  # is a read. transports map their native verb onto this before we run.
  m = req["method"]
  writing = (m == "POST" || m == "PUT" || m == "PATCH" || m == "DELETE")

  res = writing ? write(req) : read(req)

  puts "Status: #{res["status"]}"
  puts "Content-Type: #{res["content-type"]}"
  puts ""
  puts res["body"]
end
