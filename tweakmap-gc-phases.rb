$stdout.sync = true

def report(label)
  status = File.read('/proc/self/status').lines.grep(/VmRSS:|VmSize:/).map(&:strip).join(' ')
  puts "#{label}: #{status} weakmaps=#{ObjectSpace.each_object(ObjectSpace::WeakMap).count} gc=#{GC.count}"
end

report('start')
3.times do |round|
  1_000_000.times { ObjectSpace::WeakMap.new }
  report("round #{round + 1}, before GC")
  5.times do |cycle|
    GC.start
    report("round #{round + 1}, GC #{cycle + 1}")
  end
end
