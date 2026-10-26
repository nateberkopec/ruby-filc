$stdout.sync = true
$calls = 0
FINALIZER = proc { $calls += 1 }

def allocate_finalizers(count)
  count.times { ObjectSpace.define_finalizer(Object.new, FINALIZER) }
end

Integer(ARGV.fetch(0, '8')).times do |round|
  allocate_finalizers(50_000)
  5.times { GC.start; sleep 0.01 }
  rss = File.read('/proc/self/status')[/VmRSS:\s+(\d+)/, 1].to_i / 1024
  puts "round=#{round + 1} calls=#{$calls} rss=#{rss}MB"
  raise "missing finalizers: #{$calls}" unless $calls == (round + 1) * 50_000
end
