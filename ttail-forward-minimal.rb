mode = ARGV.fetch(0, 'tail')
raise "unknown mode #{mode}" unless %w[tail plain].include?(mode)
RubyVM::InstructionSequence.compile(<<~'RUBY', tailcall_optimization: mode == 'tail', trace_instruction: false).eval
  def forward_target(value)
    value
  end

  def forward_relay(...)
    forward_target(...)
  end

  def forward_entry
    forward_relay(42)
  end
RUBY
instruction = RubyVM::InstructionSequence.of(method(:forward_entry)).disasm.lines.find { |line| line.include?('mid:forward_relay') }
raise 'wrong tailcall compilation mode' unless instruction && instruction.include?('TAILCALL') == (mode == 'tail')
value = forward_entry
raise "incorrect forwarded value: #{value.inspect}" unless value == 42
puts "forwarding #{mode}: #{value}"
