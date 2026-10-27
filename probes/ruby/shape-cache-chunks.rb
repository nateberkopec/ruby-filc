objects = Array.new(128) do |index|
  klass = Class.new
  names = Array.new(48) { |field| "@cache_chunk_#{index}_#{field}" }
  klass.class_eval("def checksum; #{names.join(' + ')}; end")
  object = klass.new
  names.each_with_index { |name, field| object.instance_variable_set(name, index + field) }
  [object, names, 48 * index + (0...48).sum]
end

raise 'did not exercise multiple cache chunks' unless RubyVM.stat(:shape_cache_size) > 8192
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
puts "shape cache: #{RubyVM.stat(:shape_cache_size)} nodes; chunk boundaries, reads, copies, removal, Ractors and GC passed"
