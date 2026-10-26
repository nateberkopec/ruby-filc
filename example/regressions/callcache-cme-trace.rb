$stdout.sync = true
kind, operation, dispatch, mutation = ARGV
raise 'invalid kind' unless %w[attr struct].include?(kind)
raise 'invalid operation' unless %w[read write].include?(operation)
raise 'invalid dispatch' unless %w[direct public_send].include?(dispatch)
raise 'invalid mutation' unless %w[remove replace].include?(mutation)

klass = kind == 'struct' ? Struct.new(:x) : Class.new { attr_accessor :x }
object = klass.new
object.x = 4
method = operation == 'write' ? :x= : :x
armed = true
events = []
trace = TracePoint.new(:c_call, :c_return) do |event|
  next unless event.self.equal?(object) && event.method_id == method
  events << [event.event, event.method_id, event.callee_id, event.defined_class]
  if armed && event.event == :c_call
    armed = false
    if mutation == 'remove'
      klass.class_eval { remove_method method }
    else
      klass.define_method(method) { |*| :replacement }
    end
    GC.start(full_mark: true, immediate_sweep: true)
  end
end

result = trace.enable do
  if dispatch == 'public_send'
    operation == 'write' ? object.public_send(method, 9) : object.public_send(method)
  else
    operation == 'write' ? (object.x = 9) : object.x
  end
end
raise 'current dispatch changed' unless result == (operation == 'write' ? 9 : 4)
stored = kind == 'struct' ? object[:x] : object.instance_variable_get(:@x)
raise 'current accessor operation was lost' unless stored == (operation == 'write' ? 9 : 4)
expected = [[:c_call, method, method, klass], [:c_return, method, method, klass]]
raise "incorrect events #{events.inspect}" unless events == expected
if mutation == 'remove'
  raise 'removed method is still visible' if object.respond_to?(method)
else
  args = operation == 'write' ? [9] : []
  raise 'replacement was not installed' unless object.public_send(method, *args) == :replacement
end
puts "#{kind}/#{operation}/#{dispatch}/#{mutation}: active dispatch and event metadata preserved"
