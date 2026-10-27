operations = %w[delete delete_if reject! keep_if clear replace]
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

class SetLifetimeMarker
  attr_reader :index
  def initialize(index)
    @index = index
  end
  def hash
    @index.hash
  end
  def eql?(other)
    other.is_a?(SetLifetimeMarker) && other.index == @index
  end
end

keep = extent == 'empty' ? 0 : count / 2
expected = (0...keep).to_a
weak = ObjectSpace::WeakMap.new
held = nil
Thread.new do
  held = Set.new
  count.times do |index|
    object = SetLifetimeMarker.new(index)
    weak[object] = true
    held.add(object)
  end
  held.instance_variable_set(:@retained, :state)
  case operation
  when 'delete'
    held.to_a.each { |object| held.delete(object) if object.index >= keep }
  when 'delete_if'
    held.delete_if { |object| object.index >= keep }
  when 'reject!'
    held.reject! { |object| object.index >= keep }
  when 'keep_if'
    held.keep_if { |object| object.index < keep }
  when 'clear'
    raise 'wrong clear return' unless held.clear.equal?(held)
  when 'replace'
    replacement = held.select { |object| object.index < keep }
    raise 'wrong replace return' unless held.replace(replacement).equal?(held)
  end
  raise 'wrong remaining members' unless held.map(&:index) == expected
  nil
end.join

3.times { GC.start(full_mark: true, immediate_sweep: true) }
live = []
weak.each_key { |object| live << object.index }
raise "unexpected live markers: #{live.sort.inspect}; expected #{expected.inspect}" unless live.sort == expected
raise 'lost members or order' unless held.map(&:index) == expected
raise 'lost instance variable' unless held.instance_variable_get(:@retained) == :state
held.add(:reused)
raise 'cannot reuse set' unless held.include?(:reused) && held.size == keep + 1
puts "Set##{operation} #{count} #{extent}: removed members collected; survivors, order and reuse preserved"
