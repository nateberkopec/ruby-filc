$stdout.sync = true
shape = ARGV.fetch(0, 'simple')
sources = {
  'simple' => 'def target; 17; end',
  'optional' => 'def target(value = 17); value; end',
  'keyword' => 'def target(value: 17); value; end',
  'keyword_default' => 'def target(value: 17); value; end',
  'complex' => 'def target(value, *rest, flag:, **kw); value + rest.fetch(0) + flag + kw.fetch(:extra); end',
  'forwarding' => 'def target(...); 17; end',
  'tailcall' => 'def target; 17; end',
  'arity' => 'def target(value); value; end'
}
klass = Class.new
klass.class_eval(sources.fetch(shape))
caller_class = Class.new
if shape == 'tailcall'
  RubyVM::InstructionSequence.compile_option = {tailcall_optimization: true, trace_instruction: false}
  caller_class.class_eval('def invoke(object, &block); object.target(&block); end')
  instructions = RubyVM::InstructionSequence.of(caller_class.instance_method(:invoke)).disasm
  raise 'tailcall was not enabled' unless instructions.include?('TAILCALL')
end
seen = []
Warning.singleton_class.define_method(:warn) do |message, **|
  seen << message
  klass.class_eval { remove_method :target }
  GC.start(full_mark: true, immediate_sweep: true)
end
$VERBOSE = true
object = klass.new
value = begin
  case shape
  when 'optional'
    object.target(17) { 9 }
  when 'keyword'
    object.target(value: 17) { 9 }
  when 'complex'
    object.target(3, 5, flag: 4, extra: 5) { 9 }
  when 'forwarding'
    object.target(17, extra: 9) { 9 }
  when 'tailcall'
    caller_class.new.invoke(object) { 9 }
  else
    object.target { 9 }
  end
rescue ArgumentError => error
  raise unless shape == 'arity' && error.message.include?('given 0, expected 1')
  :arity_error
end
raise 'active method changed' unless value == (shape == 'arity' ? :arity_error : 17)
if shape == 'forwarding'
  raise 'forwarding unexpectedly warned or removed the method' unless seen.empty? && klass.method_defined?(:target)
  puts 'forwarding: forwarded block did not emit an unused-block warning'
else
  raise "warning hook did not run once: #{seen.inspect}" unless seen.size == 1 && seen.first.include?('may be ignored')
  raise 'removed method remained visible' if klass.method_defined?(:target)
  puts "#{shape}: active Ruby method survived removal and collection in Warning.warn"
end
