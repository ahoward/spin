# a spin handler is a RESOURCE you talk to. you write read and write; the
# framework handles everything else. compiled by spinel to a fast binary
# (native or wasm), reachable over any transport (HTTP, github issue, tunnel).

require_relative "spin"

def read(req)
  case resource(req)
  when ""       then reply(200, "spin: talk to a resource. try /notes")
  when "notes"  then reply(200, "all notes (id=#{resource_id(req)})")
  when "health" then reply(200, "ok")
  else               reply(404, "no such resource: #{req["path"]}")
  end
end

def write(req)
  case resource(req)
  when "notes"  then reply(201, "created a note (#{req["body"].length} bytes)")
  else               reply(405, "#{resource(req)} is read-only")
  end
end

spin_run
