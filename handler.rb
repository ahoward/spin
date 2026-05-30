# a spin handler. compiled by spinel to a fast native binary or wasm.
# routing reads like sinatra; it compiles like C.

require_relative "spin"

method, path = spin_request

if spin_get?(method, path, "/")
  spin_text(200, "hello from spin")

elsif spin_get?(method, path, "/hi/:name")
  spin_text(200, "hi #{spin_param("/hi/:name", path)}")

elsif spin_post?(method, path, "/echo")
  body = spin_body
  spin_text(201, "you said (#{body.length} bytes): #{body.chomp}")

elsif spin_delete?(method, path, "/thing/:id")
  spin_text(200, "deleted #{spin_param("/thing/:id", path)}")

else
  spin_text(404, "not found: #{method} #{path}")
end
