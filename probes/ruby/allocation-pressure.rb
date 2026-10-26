$stdout.sync = true
mode = ARGV.fetch(0)
n = Integer(ARGV.fetch(1, '1000000'))
GC.start
collections = GC.count
objects = GC.stat(:total_allocated_objects)
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
case mode
when 'while'
  i = 0
  i += 1 while i < n
when 'times'
  n.times { 1 }
when 'rand'
  n.times { rand(1000) }
when 'array-fixed'
  Array.new(n, 1)
when 'array-block'
  Array.new(n) { 1 }
when 'array-rand'
  Array.new(n) { rand(1000) }
else
  raise mode
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
objects = GC.stat(:total_allocated_objects) - objects
collections = GC.count - collections
memory = File.read('/proc/self/status')
puts "#{mode} n=#{n} elapsed=#{elapsed.round(3)} objects=#{objects} collections=#{collections} rss=#{memory[/VmRSS:\s+(\d+)/, 1]}KB peak=#{memory[/VmHWM:\s+(\d+)/, 1]}KB"
