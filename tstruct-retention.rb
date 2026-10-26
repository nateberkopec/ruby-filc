$stdout.sync = true
10.times do |round|
  10000.times do
    Struct.new('A')
    Struct.send(:remove_const, :A)
  end
  5.times { GC.start }
  memory = File.read('/proc/self/status')
  classes = ObjectSpace.each_object(Class).count
  named = ObjectSpace.each_object(Class).count { |klass| klass.name == 'Struct::A' }
  puts "round=#{round + 1} classes=#{classes} named=#{named} rss=#{memory[/VmRSS:\s+(\d+)/, 1]}KB peak=#{memory[/VmHWM:\s+(\d+)/, 1]}KB collections=#{GC.count}"
end
