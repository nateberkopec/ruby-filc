cases = %w[empty embedded heap expanded shared]
if ARGV.empty?
  require 'open3'
  require 'rbconfig'
  cases.each do |name|
    output, status = Open3.capture2e(RbConfig.ruby, __FILE__, name)
    raise "#{name}: #{output}" unless status.success?
    puts output
  end
  exit
end

mode = ARGV.fetch(0)
raise "unknown case #{mode}" unless cases.include?(mode)
class ArrayClearMarker
  attr_reader :index
  def initialize(index)
    @index = index
  end
end

weak = ObjectSpace::WeakMap.new
held = nil
Thread.new do
  count = {'empty' => 0, 'embedded' => 20, 'expanded' => 20}.fetch(mode, 100)
  held = Array.new(count) do |index|
    object = ArrayClearMarker.new(index)
    weak[object] = true
    object
  end
  if mode == 'expanded'
    80.times do |index|
      object = ArrayClearMarker.new(index + 20)
      weak[object] = true
      held << object
    end
  end
  held.instance_variable_set(:@retained, :state)
  sibling = held.dup if mode == 'shared'
  raise 'clear did not return self' unless held.clear.equal?(held)
  raise 'clear did not empty the array' unless held.empty?
  if sibling
    raise 'clear changed a shared sibling' unless sibling.map(&:index) == (0...100).to_a
  end
  nil
end.join
3.times { GC.start(full_mark: true, immediate_sweep: true) }
remaining = []
weak.each_key { |object| remaining << object.index }
raise "removed objects remain reachable: #{remaining.sort.inspect}" unless remaining.empty?
raise 'clear changed instance variables' unless held.instance_variable_get(:@retained) == :state
held << :reused
raise 'cleared array cannot be reused' unless held == [:reused]
puts "Array#clear #{mode}: removed objects collected; contents, sharing and reuse preserved"
