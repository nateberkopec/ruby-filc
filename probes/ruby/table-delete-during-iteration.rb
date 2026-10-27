class IterationDeleteKey
  attr_reader :index
  def initialize(index)
    @index = index
  end
  def hash
    0
  end
  def eql?(other)
    raise 'compared against a cleared entry' unless other.is_a?(IterationDeleteKey)
    @index == other.index
  end
end

[2, 8, 9, 100].product([Hash, Set], %w[delete clear nested]).each do |count, klass, operation|
  keys = Array.new(count) { |index| IterationDeleteKey.new(index) }
  held = klass == Hash ? keys.to_h { |key| [key, key.index] } : Set.new(keys)
  visited = []
  held.delete_if do |key, *value|
    visited << key.index
    case operation
    when 'delete'
      held.delete(key)
    when 'clear'
      held.clear
    when 'nested'
      held.delete_if { |other, *unused| other.index.even? }
    end
    true
  end
  expected = case operation
             when 'delete' then (0...count).to_a
             when 'clear' then [0]
             when 'nested' then [0, *(1...count).step(2)]
             end
  raise "wrong visits for #{klass} #{count} #{operation}: #{visited.inspect}" unless visited == expected
  raise 'failed to empty table' unless held.empty?
  puts "#{klass} #{count} #{operation}: deletion during iteration preserved"
end
