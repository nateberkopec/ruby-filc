dump_shapes = ARGV.delete('--dump-shapes')
if dump_shapes
  require 'objspace'
  require 'json'
end

objects = Array.new(128) do |index|
  klass = Class.new
  names = Array.new(48) { |field| "@cache_chunk_#{index}_#{field}" }
  klass.class_eval("def checksum; #{names.join(' + ')}; end")
  object = klass.new
  names.each_with_index { |name, field| object.instance_variable_set(name, index + field) }
  [object, names, 48 * index + (0...48).sum]
end

raise 'did not exercise multiple cache chunks' unless RubyVM.stat(:shape_cache_size) > 8192
raise 'did not exercise multiple shape chunks' unless RubyVM.stat(:next_shape_id) > 4096
3.times do
  GC.start(full_mark: true, immediate_sweep: true)
  objects.each do |object, names, expected|
    raise 'incorrect cached ivar read' unless object.checksum == expected
    copy = object.dup
    raise 'incorrect copied ivars' unless copy.checksum == expected
    names.each_with_index do |name, field|
      original = copy.instance_variable_get(name)
      raise 'incorrect ivar removal' unless copy.remove_instance_variable(name) == original
      copy.instance_variable_set(name, original + field)
    end
    raise 'incorrect rebuilt shape' unless copy.checksum == expected + (0...48).sum
  end
end
shapes_before_workers = RubyVM.stat(:next_shape_id)
workers = Array.new(4) do |worker|
  Ractor.new(worker) do |index|
    24.times do |iteration|
      object = Class.new.new
      names = Array.new(48) { |field| "@parallel_#{index}_#{iteration}_#{field}" }
      names.each_with_index { |name, field| object.instance_variable_set(name, field) }
      GC.start(full_mark: true, immediate_sweep: true) if iteration % 8 == 0
      names.each_with_index do |name, field|
        raise 'incorrect concurrent shape lookup' unless object.instance_variable_get(name) == field
      end
    end
    true
  end
end
raise 'concurrent shape construction failed' unless workers.map(&:value).all?
raise 'concurrent workers did not cross a shape chunk' unless RubyVM.stat(:next_shape_id) > shapes_before_workers + 4096
if dump_shapes
  expected_count = RubyVM.stat(:next_shape_id)
  shapes = ObjectSpace.dump_shapes(output: :string).lines.map { |line| JSON.parse(line) }
  raise 'shape dump omitted shapes' unless shapes.size == expected_count
  raise 'shape dump changed IDs' unless shapes.each_with_index.all? { |shape, index| shape.fetch('id') == index }
end
puts "shapes: #{RubyVM.stat(:next_shape_id)}; cache: #{RubyVM.stat(:shape_cache_size)} nodes; chunk boundaries, reads, copies, removal, Ractors and GC passed"
