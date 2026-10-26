mode = ARGV.fetch(0, 'both')
raise "unknown mode #{mode}" unless %w[both outgoing].include?(mode)
source = <<~'RUBY'
  class TailForwarder
    attr_reader :keys

    def initialize
      @keys = ObjectSpace::WeakMap.new
    end

    def relay(...)
      watched = 'x' * 65_536
      @keys[watched] = true
      target(capture(...))
    end

    def capture(depth, left, right, label:, **keywords, &block)
      [depth, left, right, label, keywords, block]
    end

    def target(state)
      depth, left, right, label, keywords, block = state
      return [left, right, label, keywords, block.call] if depth.zero?
      relay(depth - 1, right, left, label: label, **keywords, &block)
    end
  end
RUBY
if mode == 'outgoing'
  call = 'relay(depth - 1, right, left, label: label, **keywords, &block)'
  raise 'missing recursive call' unless source.sub!(call, "result = #{call}\n      raise unless result.is_a?(Array)\n      result")
end
code = RubyVM::InstructionSequence.compile(source, tailcall_optimization: true, trace_instruction: false)
code.eval
worker = TailForwarder.new
relay = RubyVM::InstructionSequence.of(worker.method(:relay)).disasm
relay_call = relay.lines.find { |line| line.include?('mid:target') }
forwarding_call = relay.lines.find { |line| line.include?('mid:capture') }
raise 'forwarding not compiled' unless forwarding_call&.include?('sendforward')
raise 'tailcall from forwarding method not compiled' unless relay_call&.include?('TAILCALL')
target = RubyVM::InstructionSequence.of(worker.method(:target)).disasm
target_call = target.lines.find { |line| line.include?('mid:relay') }
raise 'missing recursive call instruction' unless target_call
raise 'incorrect incoming tailcall mode' unless target_call.include?('TAILCALL') == (mode == 'both')

fiber = Fiber.new do
  result = worker.relay(100, :left, :right, label: :label, extra: :extra) { :block }
  raise "arguments or block changed: #{result.inspect}" unless result == [:left, :right, :label, {extra: :extra}, :block]
  Fiber.yield :ready
end
raise 'fiber did not suspend' unless fiber.resume == :ready && fiber.alive?
GC.start(full_mark: true, immediate_sweep: true)
remaining = worker.keys.keys.size
puts "forwarding_tailcall mode=#{mode} remaining=#{remaining} expected=0 alive=#{fiber.alive?}"
raise 'retired forwarding frames retain objects' unless remaining.zero?
fiber.resume
