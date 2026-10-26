$stdout.sync = true
case ARGV.fetch(0)
when 'enable_race'
  objects = Array.new(500_000) { Object.new }
  GC.disable
  worker = Ractor.new do
    Ractor.receive
    sleep 0.01
    GC.enable
  end
  worker << true
  GC.start
  observed = [worker.value, GC.enable]
  puts "enable_race=#{observed.inspect} objects=#{objects.size}"
  raise 'GC.start overwrote or exposed the logical GC state' unless observed == [true, false]
when 'disabled_count'
  GC.start
  GC.disable
  before = GC.count
  objects = []
  300_000.times { objects << 'x' * 64 }
  sleep 0.2
  after = GC.count
  puts "disabled_count=#{[before, after].inspect} objects=#{objects.size}"
  raise 'automatic cycles counted while Ruby GC is disabled' unless after == before
  GC.start
  explicit = GC.count
  raise 'explicit collection was not counted' unless explicit > after
  raise 'explicit collection enabled GC' unless GC.enable
  puts "explicit_count=#{explicit}"
when 'overlap'
  objects = Array.new(100_000) { Object.new }
  workers = Array.new(4) do
    Ractor.new { Ractor.receive; GC.start; true }
  end
  GC.disable
  before = GC.count
  workers.each { |worker| worker << true }
  workers.each { |worker| raise 'worker failed' unless worker.value }
  after = GC.count
  raise 'concurrent explicit collections counted incorrectly' unless (1..4).cover?(after - before)
  100_000.times { objects << Object.new }
  sleep 0.1
  raise 'automatic cycles counted after explicit collections' unless GC.count == after
  raise 'explicit collections enabled GC' unless GC.enable
  puts "overlap_count=#{[before, after].inspect} objects=#{objects.size}"
when 'atomic_transitions'
  10.times do
    ['enable', 'disable'].each do |operation|
      workers = Array.new(8) { Ractor.new(operation) { |method| Ractor.receive; GC.public_send(method) } }
      operation == 'enable' ? GC.disable : GC.enable
      workers.each { |worker| worker << true }
      results = workers.map(&:value)
      expected_true = operation == 'enable' ? 1 : 7
      raise "non-atomic #{operation}: #{results.inspect}" unless results.count(true) == expected_true
      GC.enable
    end
  end
  puts 'atomic_transitions=passed'
when 'enable_during_overlap'
  objects = Array.new(500_000) { Object.new }
  workers = Array.new(4) { Ractor.new { Ractor.receive; GC.start; true } }
  GC.disable
  workers.each { |worker| worker << true }
  sleep 0.01
  previous = GC.enable
  workers.each { |worker| worker.value }
  observed = [previous, GC.enable]
  puts "enable_during_overlap=#{observed.inspect} objects=#{objects.size}"
  raise 'overlapping collections overwrote logical state' unless observed == [true, false]
when 'fork_count'
  GC.start
  before = GC.count
  pid = fork do
    raise 'fork reset collection count' unless GC.count >= before
    GC.disable
    disabled = GC.count
    GC.start
    raise 'forked explicit collection was not counted' unless GC.count > disabled
    raise 'forked explicit collection enabled GC' unless GC.enable
  end
  Process.wait(pid)
  raise 'forked counter probe failed' unless $?.success?
  puts 'fork_count=passed'
else
  raise 'unknown scenario'
end
