# a transport-agnostic handler: request comes via ENV + stdin (CGI-style),
# response goes to stdout. compiles to a standalone native binary.

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
