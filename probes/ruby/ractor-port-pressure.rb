$stdout.sync = true
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
monitor = Thread.new do
  loop do
    rss = File.read('/proc/self/status')[/VmRSS:\s+(\d+)/, 1].to_i / 1024
    puts "#{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)}s #{rss}MB #{GC.stat(:total_allocated_objects)} objects #{GC.count} collections"
    sleep 0.5
  end
end

def ractor_job(job_count, array_size)
  port = Ractor::Port.new
  workers = (1..4).map do
    Ractor.new(port) do |job_port|
      while job = Ractor.receive
        result = job.map { |x| x * 2 }.sum
        job_port.send result
      end
    end
  end
  jobs = Array.new(job_count) { Array.new(array_size) { rand(1000) } }
  jobs.each_with_index { |job, i| workers[i % 4].send(job) }
  jobs.size.times.map { port.receive }
end

Array.new(Integer(ARGV.fetch(0, '10'))) { Thread.new { ractor_job(50, 20_000) } }.each(&:join)
monitor.kill
puts 'ok'
