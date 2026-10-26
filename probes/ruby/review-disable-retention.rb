$stdout.sync = true
objects = Array.new(500_000) { Object.new }
weak = ObjectSpace::WeakMap.new
worker = Ractor.new { Ractor.receive; GC.start; true }
GC.disable
1_000.times { weak[Object.new] = true }
GC.enable
worker << true
sleep(Float(ARGV.fetch(0, '0.01')))
previous = GC.disable
worker.value
alive = weak.size
puts "remaining=#{alive} previous=#{previous} objects=#{objects.size}"
raise 'concurrent disable prevented explicit collection' unless alive < 10
raise 'logical disabled state was lost' unless GC.enable
