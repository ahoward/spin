# spin.rb — the routing layer. require this from a handler.
#
# the simplicity bar is sinatra / lib/site.rb: a route is a method + a path
# + what to do. but a spin handler is AOT-compiled by spinel, so routing
# runs INSIDE the compiled binary and must use only what spinel compiles.
# spinel infers homogeneous typed structures and does not do runtime
# proc-tables — so spin's routing is built from plain helpers and a flat
# if/elsif dispatch, not a registry of blocks.
#
# you write (handler.rb):
#
#     require_relative "spin"
#
#     method, path = spin_request
#
#     if    spin_get?(method, path, "/")            then spin_text(200, "hello")
#     elsif spin_get?(method, path, "/hi/:name")    then spin_text(200, "hi #{spin_param("/hi/:name", path)}")
#     elsif spin_post?(method, path, "/echo")       then spin_text(201, "you said: #{spin_body}")
#     else                                                spin_text(404, "not found: #{path}")
#     end
#
# that is the whole framework surface. five helpers + a request reader.
# it reads like sinatra, it compiles like C.

# --- request --------------------------------------------------------------

# read the request line: [method, path]. ENV carries metadata (CGI contract).
def spin_request
  method = ENV["REQUEST_METHOD"] || "GET"
  path   = ENV["PATH_INFO"] || "/"
  [method, path]
end

# read the whole request body from stdin (bare gets — STDIN.gets unsupported).
def spin_body
  body = ""
  while (line = gets)
    body = body + line
  end
  body
end

# --- matching --------------------------------------------------------------

# does `pattern` (e.g. "/hi/:name") match `path` (e.g. "/hi/bob")?
# segment-by-segment; ":name" segments match any single segment.
def spin_match?(pattern, path)
  pp = pattern.split("/")
  ps = path.split("/")
  return false if pp.length != ps.length
  i = 0
  while i < pp.length
    seg = pp[i]
    got = ps[i]
    if seg.length > 0 && seg[0] == ":"
      # param segment — matches anything non-empty
      return false if got.length == 0
    elsif seg != got
      return false
    end
    i = i + 1
  end
  true
end

# extract the value of the FIRST :param in `pattern` from `path`.
# (one param per route keeps it spinel-simple; multi-param is an issue.)
def spin_param(pattern, path)
  pp = pattern.split("/")
  ps = path.split("/")
  return "" if pp.length != ps.length
  i = 0
  while i < pp.length
    seg = pp[i]
    if seg.length > 0 && seg[0] == ":"
      return ps[i]
    end
    i = i + 1
  end
  ""
end

# method+path predicates — the sinatra-flat verbs.
def spin_get?(method, path, pattern)
  method == "GET" && spin_match?(pattern, path)
end

def spin_post?(method, path, pattern)
  method == "POST" && spin_match?(pattern, path)
end

def spin_put?(method, path, pattern)
  method == "PUT" && spin_match?(pattern, path)
end

def spin_delete?(method, path, pattern)
  method == "DELETE" && spin_match?(pattern, path)
end

# --- response --------------------------------------------------------------

# emit a CGI response: status line + headers + blank + body.
def spin_respond(status, content_type, body)
  puts "Status: #{status}"
  puts "Content-Type: #{content_type}"
  puts ""
  puts body
end

def spin_text(status, body)
  spin_respond(status, "text/plain", body)
end

def spin_json(status, body)
  spin_respond(status, "application/json", body)
end

def spin_html(status, body)
  spin_respond(status, "text/html", body)
end
