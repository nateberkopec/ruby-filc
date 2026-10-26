class StackRetirement
  def self.populate(depth, keys, held, mode)
    return if depth.zero?
    object = 'x' * 65_536
    keys[object] = depth
    held << -> { object } if mode == 'closures' && depth % 10 == 0
    case mode
    when 'raise'
      raise 'unwind' if depth == 1
    when 'throw'
      throw :unwind if depth == 1
    when 'cframes'
      [object].each { populate(depth - 1, keys, held, mode) }
      return nil
    end
    populate(depth - 1, keys, held, mode)
    nil
  end

  def self.forward(...)
    forwarded(...)
  end

  def self.forwarded(depth, keys, *rest, label:, **keywords, &block)
    raise unless rest == [:left, :right] && label == :label && keywords == {extra: :extra} && block.call == :block
    return if depth.zero?
    object = 'x' * 65_536
    keys[object] = depth
    forward(depth - 1, keys, *rest, label: label, **keywords, &block)
    nil
  end
end

class StackReceiver < String
  def populate(depth, keys)
    keys[self] = depth
    self.class.new('x' * 65_536).populate(depth - 1, keys) if depth > 1
    nil
  end
end

mode = ARGV.fetch(0)
raise "unknown mode #{mode}" unless %w[normal raise throw closures cframes receiver forwarding tailcall traced].include?(mode)
keys = ObjectSpace::WeakMap.new
held = []
events = []
trace = if mode == 'traced'
  TracePoint.new(:return, :c_return) do |event|
    if event.method_id == :populate
      events << [event.event, event.defined_class, event.return_value]
      GC.start(full_mark: true, immediate_sweep: true)
    end
  end
end

if mode == 'tailcall'
  code = RubyVM::InstructionSequence.compile(<<~'RUBY', tailcall_optimization: true, trace_instruction: false)
    def tail_retire(depth, keys, left, right)
      object = 'x' * 65_536
      keys[object] = depth
      return [left, right] if depth.zero?
      tail_retire(depth - 1, keys, right, left)
    end
  RUBY
  raise 'tailcall not compiled' unless code.disasm.include?('TAILCALL')
  code.eval
end

fiber = Fiber.new do
  trace&.enable
  case mode
  when 'raise'
    begin
      StackRetirement.populate(100, keys, held, mode)
    rescue RuntimeError => error
      raise unless error.message == 'unwind'
    end
  when 'throw'
    catch(:unwind) { StackRetirement.populate(100, keys, held, mode) }
  when 'receiver'
    StackReceiver.new('x' * 65_536).populate(100, keys)
  when 'forwarding'
    StackRetirement.forward(100, keys, :left, :right, label: :label, extra: :extra) { :block }
  when 'tailcall'
    raise 'tailcall arguments changed' unless tail_retire(100, keys, :left, :right) == [:left, :right]
  else
    StackRetirement.populate(100, keys, held, mode)
  end
  [:retired].each { |value| raise unless value == :retired } if mode == 'cframes'
  trace&.disable
  Fiber.yield :ready
end
raise 'fiber did not suspend' unless fiber.resume == :ready && fiber.alive?
GC.start(full_mark: true, immediate_sweep: true)
remaining = keys.keys.size
expected = mode == 'closures' ? 10 : 0
puts "mode=#{mode} remaining=#{remaining} expected=#{expected} alive=#{fiber.alive?}"
raise 'retired frames retained objects or live closures lost them' unless remaining == expected
raise 'captured locals changed' unless held.all? { |block| block.call.bytesize == 65_536 }
if trace
  raise 'missing return callbacks' unless events.size == 101
  raise 'incorrect return callback' unless events.all? { |event, owner, value| event == :return && owner == StackRetirement.singleton_class && value.nil? }
end
fiber.resume
raise 'fiber did not finish' if fiber.alive?
