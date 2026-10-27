if ARGV.empty?
  require 'open3'
  require 'rbconfig'
  %w[hash set native].each do |kind|
    output, status = Open3.capture2e(RbConfig.ruby, '-I', $LOAD_PATH.join(File::PATH_SEPARATOR), __FILE__, kind)
    raise "#{kind}: #{output}" unless status.success?
    puts output
  end
  exit
end

kind = ARGV.fetch(0)
raise 'invalid table kind' unless %w[hash set native].include?(kind)
require 'st_table_lifetime' if kind == 'native'

class CompactionLifetimeMarker
  attr_reader :index
  def initialize(index)
    @index = index
  end
  def hash
    0 # Also exercise collision chains across deletion and compaction.
  end
  def eql?(other)
    equal?(other)
  end
end

def keys(table)
  table.is_a?(Set) ? table.to_a : table.to_a.map(&:first)
end

def insert(table, key)
  table.is_a?(Set) ? table.add(key) : table[key] = key
end

weak = ObjectSpace::WeakMap.new
held = nil
expected = (1...64).step(2).to_a
Thread.new do
  held = {'hash' => Hash, 'set' => Set, 'native' => (NativeLifetimeTable if kind == 'native')}.fetch(kind).new
  128.times do |index|
    object = CompactionLifetimeMarker.new(index)
    weak[object] = true
    insert(held, object)
  end
  keys(held).each { |object| held.delete(object) if object.index.even? }
  # Reuse a full entry array with holes, then delete some of the moved entries.
  insert(held, :sentinel)
  keys(held).each { |object| held.delete(object) if object != :sentinel && object.index >= 64 }
  nil
end.join

3.times { GC.start(full_mark: true, immediate_sweep: true) }
live = []
weak.each_key { |object| live << object.index }
raise "unexpected live markers: #{live.sort.inspect}; expected #{expected.inspect}" unless live.sort == expected
remaining = keys(held)
raise 'lost sentinel or order' unless remaining.pop == :sentinel && remaining.map(&:index) == expected
raise 'lost values' if kind != 'set' && held.to_a.any? { |key, value| !key.equal?(value) }
insert(held, :reused)
raise 'cannot reuse table' unless keys(held).last == :reused
puts "#{kind}: deleted entries and compaction duplicates reclaimed; survivors, order and reuse preserved"
