# a spin app, written in the declarative resource DSL.
#
# this is real ruby — `resource`/`read`/`write` are spin DSL methods. it is
# NOT compiled directly; `spin build examples/notes.rb` evaluates it at build
# time, codegens a spinel-compilable handler (examples/notes.spin.rb), and
# compiles that.
#
# inside a read/write block, `req` is the request bag (string→string) and
# `reply`/`resource_id`/`resource` are available (they live in the compiled
# runtime, spin.rb).

resource "notes" do
  read  { |req| reply(200, "all notes (id=#{resource_id(req)})") }
  write { |req| reply(201, "wrote #{req["body"].length} bytes to notes") }
end

resource "health" do
  read { |req| reply(200, "ok") }
end

resource "echo" do
  write { |req| reply(200, req["body"]) }
end
