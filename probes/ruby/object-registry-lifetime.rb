require 'open3'
require 'rbconfig'

if ARGV.empty?
  counts = %w[plain suspended].map do |mode|
    output, errors, status = Open3.capture3(RbConfig.ruby, __FILE__, mode)
    raise "#{mode} probe failed: #{errors}" unless status.success?
    Integer(output.strip)
  end
  raise "suspended ObjectSpace enumeration retained unrelated objects: #{counts.inspect}" unless counts[1] <= counts[0] + 1
  puts "ObjectSpace lifetime: plain=#{counts[0]}, suspended=#{counts[1]}"
  exit
end

class RegistryLifetimeMarker
end

held = []
weak = ObjectSpace::WeakMap.new
Thread.new do
  100.times do
    object = RegistryLifetimeMarker.new
    held << object
    weak[object] = true
  end
  nil
end.join

case ARGV.fetch(0)
when 'suspended'
  iterator = ObjectSpace.each_object(Class)
  iterator.next
when 'plain'
else
  raise 'unknown registry lifetime scenario'
end
held.fill(nil)
held.clear
3.times { GC.start(full_mark: true, immediate_sweep: true) }
remaining = 0
weak.each_key { remaining += 1 }
raise 'ObjectSpace enumerator stopped unexpectedly' if iterator && !iterator.next.is_a?(Class)
puts remaining
