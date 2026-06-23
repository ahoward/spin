# spin/envelope.rb — the envelope (adapter side). the wire format IS http.
#
# a spin handler reads a minimal http/1.1 request on stdin and writes a
# minimal http response on stdout. symmetric, standard, line-oriented. every
# adapter (HTTP, github, CLI) uses this to talk to a handler, so the binary
# boundary speaks ONE format and a new transport is just "build a bag, hand
# it here." see docs/envelope.md.

require 'open3'

module Spin
  module Envelope
    module_function

    # encode a request bag → an http/1.1 request string.
    #   bag["verb"]  → request-line method (READ/WRITE; or pass GET/POST etc.)
    #   bag["path"]  → request-line path
    #   bag["body"]  → after the blank line
    #   everything else → header lines (verbatim keys), except reserved.
    RESERVED_REQ = %w[verb path body].freeze

    def encode_request(bag)
      verb = (bag['verb'] || 'read').to_s.upcase
      path = bag['path'] || '/'
      lines = ["#{verb} #{path}"]
      bag.each do |k, v|
        next if RESERVED_REQ.include?(k.to_s)
        lines << "#{k}: #{v}"
      end
      lines << '' # blank line
      body = bag['body'].to_s
      lines.join("\n") + "\n" + body
    end

    # parse an http response string → a response bag.
    #   "200 OK" / "Status: 200" → status
    #   header lines → keys (verbatim, lowercased)
    #   after blank line → body
    def decode_response(out)
      bag = { 'status' => '200', 'content-type' => 'text/plain' }
      head, _, body = out.partition(/\r?\n\r?\n/)
      first = true
      head.each_line do |line|
        line = line.strip
        if first
          first = false
          # accept "200 OK" (http status line) or "Status: 200" (cgi)
          if line =~ /\A(\d{3})\b/
            bag['status'] = Regexp.last_match(1)
            next
          elsif line =~ /\AStatus:\s*(\d+)/i
            bag['status'] = Regexp.last_match(1)
            next
          end
        end
        next if line.empty?
        if line =~ /\A([^:]+):\s*(.*)\z/
          bag[Regexp.last_match(1).strip.downcase] = Regexp.last_match(2).strip
        end
      end
      bag['body'] = body
      bag
    end

    # collapse a transport's native verb to read|write.
    def collapse_verb(native)
      m = native.to_s.upcase
      %w[POST PUT PATCH DELETE WRITE].include?(m) ? 'write' : 'read'
    end

    # run a handler with a request bag; return the decoded response bag.
    # native binaries by default; wasm handlers pass wasm: true.
    def call(handler, bag, command: nil, wasm: false, wasmtime: nil)
      request = encode_request(bag)

      if wasm
        wasmtime ||= File.expand_path('~/.wasmtime/bin/wasmtime')
        cmd = [wasmtime, 'run', handler]
      else
        cmd = command || [File.expand_path(handler)]
      end

      stdout, stderr, status = Open3.capture3(*cmd, stdin_data: request)
      unless status.success?
        return {
          'status' => '500', 'content-type' => 'text/plain',
          'body' => "spin: handler exited #{status.exitstatus}\n\n#{stderr}"
        }
      end
      decode_response(stdout)
    end
  end
end
