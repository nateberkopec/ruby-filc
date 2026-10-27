# Run each case in a separate process so earlier cases cannot retain markers.
operations = %w[pop shift delete_at select reject replace]
shapes = %w[small embedded heap expanded]
if ARGV.empty?
  require 'open3'
  require 'rbconfig'
  operations.product(shapes, %w[partial empty]).each do |arguments|
    output, status = Open3.capture2e(RbConfig.ruby, __FILE__, *arguments)
    raise "#{arguments.join(' ')}: #{output}" unless status.success?
    puts output
  end
  exit
end

operation, shape, extent = ARGV
raise 'invalid operation' unless operations.include?(operation)
raise 'invalid shape' unless shapes.include?(shape)
raise 'invalid extent' unless %w[partial empty].include?(extent)

class ArrayShrinkMarker
  attr_reader :index
  def initialize(index)
    @index = index
  end
end

count = {'small' => 2, 'embedded' => 20}.fetch(shape, 100)
keep = extent == 'empty' ? 0 : count / 2
expected = operation == 'shift' ? (count - keep...count).to_a : (0...keep).to_a
weak = ObjectSpace::WeakMap.new
held = nil
Thread.new do
  build = lambda do |index|
    object = ArrayShrinkMarker.new(index)
    weak[object] = true
    object
  end
  held = Array.new(shape == 'expanded' ? 20 : count, &build)
  (20...count).each { |index| held << build.call(index) } if shape == 'expanded'
  held.instance_variable_set(:@retained, :state)
  case operation
  when 'pop'
    (count - 1).downto(keep) do |index|
      raise 'wrong popped value' unless held.pop.index == index
    end
  when 'shift'
    (count - keep).times do |index|
      raise 'wrong shifted value' unless held.shift.index == index
    end
  when 'delete_at'
    (count - 1).downto(keep) do |index|
      raise 'wrong deleted value' unless held.delete_at(-1).index == index
    end
  when 'select'
    raise 'wrong select return' unless held.select! { |object| object.index < keep }.equal?(held)
  when 'reject'
    raise 'wrong reject return' unless held.reject! { |object| object.index >= keep }.equal?(held)
  when 'replace'
    replacement = held.select { |object| object.index < keep }
    raise 'wrong replace return' unless held.replace(replacement).equal?(held)
  end
  raise 'wrong remaining values' unless held.map(&:index) == expected
  nil
end.join

3.times { GC.start(full_mark: true, immediate_sweep: true) }
live = []
weak.each_key { |object| live << object.index }
raise "unexpected live markers: #{live.sort.inspect}; expected #{expected.inspect}" unless live.sort == expected
raise 'lost surviving values' unless held.map(&:index) == expected
raise 'lost instance variable' unless held.instance_variable_get(:@retained) == :state
held << :reused
raise 'cannot reuse array' unless held.last == :reused && held.size == keep + 1
puts "Array##{operation} #{shape} #{extent}: removed objects collected; survivors and reuse preserved"
