$stdout.sync = true
parent = Class.new
children = Array.new(10_000) { Class.new(parent) }
collector = Ractor.new { Ractor.receive; 100.times { GC.start }; true }
collector << true
100.times do
  found = parent.subclasses
  raise 'subclasses lost or duplicated live classes' unless found.size == children.size && found.uniq.size == children.size
  raise 'unrelated subclass returned' unless found.all? { |child| child.superclass == parent }
end
raise 'collector failed' unless collector.value
puts 'concurrent collection preserved all 10000 live subclasses across 100 enumerations'
writers = Array.new(4) do
  Ractor.new(parent) do |base|
    owned = Array.new(2_000) { Class.new(base) }
    GC.start
    owned
  end
end
100.times do
  found = parent.subclasses
  raise 'concurrent insertion duplicated a subclass' unless found.size == found.uniq.size
  raise 'concurrent insertion returned an unrelated class' unless found.all? { |child| child.superclass == parent }
end
children.concat(writers.flat_map(&:value))
raise 'completed insertions were lost' unless parent.subclasses.size == children.size
begin
  GC.stress = true
  raise 'stress collection lost subclasses' unless parent.subclasses.size == children.size
ensure
  GC.stress = false
end
puts 'concurrent insertion and forced collection preserved all 18000 live subclasses'
