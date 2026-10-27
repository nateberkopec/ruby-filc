operations = %w[delete shift delete_if reject select clear replace]
if ARGV.empty?
  require 'open3'
  require 'rbconfig'
  operations.product([2, 8, 9, 100], %w[partial empty]).each do |operation, count, extent|
    next if operation == 'clear' && extent == 'partial'
    args = [operation, count.to_s, extent]
    output, status = Open3.capture2e(RbConfig.ruby, __FILE__, *args)
    raise "#{args.join(' ')}: #{output}" unless status.success?
    puts output
  end
  exit
end

operation, count, extent = ARGV
count = Integer(count)
raise 'invalid operation' unless operations.include?(operation)
raise 'invalid count' unless [2, 8, 9, 100].include?(count)
raise 'invalid extent' unless %w[partial empty].include?(extent)
raise 'clear cannot retain a subset' if operation == 'clear' && extent != 'empty'

class HashLifetimeMarker
  attr_reader :index, :kind
  def initialize(index, kind)
    @index, @kind = index, kind
  end
  def hash
    @index.hash
  end
  def eql?(other)
    other.is_a?(HashLifetimeMarker) && other.index == @index && other.kind == @kind
  end
end

keep = extent == 'empty' ? 0 : count / 2
indices = operation == 'shift' ? (count - keep...count).to_a : (0...keep).to_a
expected = indices.flat_map { |index| [[index, :key], [index, :value]] }
weak = ObjectSpace::WeakMap.new
held = nil
Thread.new do
  held = {}
  count.times do |index|
    key = HashLifetimeMarker.new(index, :key)
    value = HashLifetimeMarker.new(index, :value)
    weak[key] = weak[value] = true
    held[key] = value
  end
  held.instance_variable_set(:@retained, :state)
  held.default = :default
  case operation
  when 'delete'
    held.keys.each do |key|
      next if key.index < keep
      raise 'wrong deleted value' unless held.delete(key).index == key.index
    end
  when 'shift'
    (count - keep).times do |index|
      pair = held.shift
      raise 'wrong shifted pair' unless pair.map(&:index) == [index, index]
    end
  when 'delete_if'
    held.delete_if { |key, value| key.index >= keep }
  when 'reject'
    held.reject! { |key, value| key.index >= keep }
  when 'select'
    held.select! { |key, value| key.index < keep }
  when 'clear'
    raise 'wrong clear return' unless held.clear.equal?(held)
  when 'replace'
    replacement = held.select { |key, value| key.index < keep }
    replacement.default = :default
    raise 'wrong replace return' unless held.replace(replacement).equal?(held)
  end
  raise 'wrong remaining keys' unless held.keys.map(&:index) == indices
  nil
end.join

3.times { GC.start(full_mark: true, immediate_sweep: true) }
live = []
weak.each_key { |object| live << [object.index, object.kind] }
raise "unexpected live markers: #{live.sort.inspect}; expected #{expected.inspect}" unless live.sort == expected.sort
raise 'lost values or order' unless held.map { |key, value| [key.index, value.index] } == indices.map { |index| [index, index] }
raise 'lost instance variable' unless held.instance_variable_get(:@retained) == :state
raise 'lost default value' unless held[:missing] == :default
held[:reused] = :yes
raise 'cannot reuse hash' unless held[:reused] == :yes && held.size == keep + 1
puts "Hash##{operation} #{count} #{extent}: removed keys/values collected; survivors, order and reuse preserved"
