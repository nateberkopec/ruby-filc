$stdout.sync = true
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
monitor = Thread.new do
  loop do
    rss = File.read('/proc/self/status')[/VmRSS:\s+(\d+)/, 1].to_i / 1024
    puts "#{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)}s #{rss}MB #{GC.stat(:total_allocated_objects)} objects #{GC.count} collections"
    sleep 0.1
  end
end

mode = ARGV.fetch(0)
thread_count = Integer(ARGV.fetch(1, '10'))
threads = Array.new(thread_count) do
  Thread.new do
    jobs = Array.new(50) { Array.new(20_000) { rand(1000) } }
    case mode
    when 'array'
      jobs
    when 'map'
      jobs.map { |job| job.map { |x| x * 2 }.sum }
    when 'copy'
      jobs.map { |job| Ractor.new(job) { |array| array.size }.value }
    when 'share'
      jobs.each { |job| Ractor.make_shareable(job) }
    end
  end
end
threads.each(&:join)
GC.start
rss = File.read('/proc/self/status')[/VmRSS:\s+(\d+)/, 1].to_i / 1024
puts "done #{rss}MB #{GC.stat(:total_allocated_objects)} objects #{GC.count} collections"
monitor.kill
