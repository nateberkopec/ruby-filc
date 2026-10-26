$stdout.sync = true
parent = Class.new
seed = Class.new(parent)
writers = Array.new(4) do
  Ractor.new(parent) do |base|
    Ractor.receive
    Array.new(1_000) { Class.new(base) }
  end
end
writers.each { |writer| writer << true }
observations = 0
100.times do
  parent.subclasses.each do |klass|
    klass.hash
    raise 'subclass has an invalid real class' unless klass.class == Class
    raise 'singleton ancestry was incomplete' unless klass.singleton_class.ancestors.include?(parent.singleton_class)
    observations += 1
  end
end
children = writers.flat_map(&:value)
raise 'subclasses lost' unless parent.subclasses.size == children.size + 1
raise 'no classes inspected' unless observations.positive?
raise 'seed subclass lost' unless parent.subclasses.include?(seed)
puts "#{observations} observations of complete class and singleton hierarchies; #{children.size} new subclasses retained"
