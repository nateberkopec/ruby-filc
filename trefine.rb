$stdout.sync = true
10.times do |round|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  100.times do
    Class.new { include Enumerable }
    Module.new { refine Enumerable do; def foo; end; end }
  end
  GC.start
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  rss = File.read('/proc/self/status')[/VmRSS:\s+(\d+)/, 1].to_i / 1024
  puts "#{round}: #{elapsed.round(3)}s #{rss}MB"
end
