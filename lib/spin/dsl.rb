# spin/dsl.rb — the build-time DSL context.
#
# this is the genius bit: the authoring file is REAL RUBY, evaluated here in
# full CRuby (unconstrained), recording resource/read/write declarations into
# a table. the codegen (codegen.rb) then expands that table into the boring
# spinel-compilable handler. ergonomics live here; compilability lives in the
# emitted output.
#
# a spin source file (app.rb) looks like:
#
#   resource "notes" do
#     read  { |req| reply(200, "all notes (id=#{resource_id(req)})") }
#     write { |req| reply(201, "wrote #{req["body"].length} bytes") }
#   end
#
#   resource "health" do
#     read { |req| reply(200, "ok") }
#   end
#
# we don't CALL the blocks (they reference reply/resource_id which only exist
# in the compiled runtime). we capture each block's source location and later
# extract its body text via Prism, splicing it into a generated case branch.

require 'prism'

module Spin
  # one declared resource: a name + an optional read block + optional write.
  Resource = Struct.new(:name, :read_block, :write_block)

  # the recorder. `instance_eval` a source file against an instance of this;
  # resource/read/write populate @resources without executing block bodies.
  class DSL
    attr_reader :resources

    def initialize
      @resources = []
      @current = nil
    end

    def self.load(path)
      src = File.read(path)
      dsl = new
      # eval in this context so resource/read/write resolve to our methods.
      # __FILE__/__LINE__ set so block source_locations point at `path`.
      dsl.instance_eval(src, File.expand_path(path), 1)
      dsl
    end

    def resource(name, &block)
      @current = Resource.new(name.to_s, nil, nil)
      instance_eval(&block) if block
      @resources << @current
      @current = nil
    end

    def read(&block)
      raise Error, '`read` outside a `resource` block' unless @current
      @current.read_block = block
    end

    def write(&block)
      raise Error, '`write` outside a `resource` block' unless @current
      @current.write_block = block
    end

    class Error < StandardError; end
  end

  # extract the BODY SOURCE TEXT of a captured block, via Prism.
  # a block `{ |req| reply(200, "x") }` → "reply(200, \"x\")".
  # works for both brace and do/end blocks, single or multi statement.
  module BlockSource
    module_function

    def for(block)
      file, line = block.source_location
      return nil unless file && File.exist?(file)

      @cache ||= {}
      result = (@cache[file] ||= Prism.parse_file(file))
      source = File.read(file)

      node = find_block_at(result.value, line)
      return nil unless node

      body = node.body # a StatementsNode or nil
      return '' unless body

      loc = body.location
      source.byteslice(loc.start_offset, loc.length)
    end

    # walk the AST for a BlockNode whose opening line == `line`.
    def find_block_at(node, line)
      return nil unless node.is_a?(Prism::Node)
      if node.is_a?(Prism::BlockNode) && node.location.start_line == line
        return node
      end
      node.compact_child_nodes.each do |child|
        found = find_block_at(child, line)
        return found if found
      end
      nil
    end
  end
end
