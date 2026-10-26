locals = Array.new(64) { |index| "local#{index} = nil" }.join("\n")
arguments = Array.new(20_000, 'nil').join(',')
code = RubyVM::InstructionSequence.compile(<<~RUBY, tailcall_optimization: true, trace_instruction: false)
  def overflow_sink(*arguments)
    raise 'oversized frame should not execute'
  end
  def oversized_frame
    overflow_sink(#{arguments})
  end
  def retire_tail(keys)
    #{locals}
    watched = 'x' * 65_536
    keys[watched] = true
    oversized_frame
  end
RUBY
raise 'tailcall not compiled' unless code.disasm.include?('TAILCALL')
code.eval
stack_max = RubyVM::InstructionSequence.of(method(:oversized_frame)).to_a[4].fetch(:stack_max)
raise 'callee stack requirement too small' unless stack_max >= 20_000
keys = ObjectSpace::WeakMap.new
fiber = Fiber.new do
  raised = false
  begin
    retire_tail(keys)
  rescue SystemStackError
    raised = true
  end
  raise 'expected stack overflow' unless raised
  Fiber.yield :overflow
end
raise 'fiber did not suspend' unless fiber.resume == :overflow && fiber.alive?
GC.start(full_mark: true, immediate_sweep: true)
remaining = keys.keys.size
puts "tailcall_overflow remaining=#{remaining} expected=0 alive=#{fiber.alive?} stack_max=#{stack_max}"
raise 'failed tailcall frame retains object' unless remaining.zero?
fiber.resume
