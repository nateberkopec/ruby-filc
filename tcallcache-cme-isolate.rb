$stdout.sync = true
mode = ARGV.fetch(0)
count = Integer(ARGV.fetch(1, '1'))
raise ArgumentError, mode unless %w[keep replace release].include?(mode)
raise ArgumentError, count unless count.positive?

sites = Array.new(count) { eval('->(value) { value.cached_byte }') }
watched, held = Fiber.new do
  watched = ObjectSpace::WeakMap.new
  held = []
  500.times do |index|
    klass = Class.new(String) do
      def cached_byte
        getbyte(0)
      end
    end
    raise 'bad dispatch' unless sites[index % count].call(klass.new('x')) == 120
    watched[klass] = index
    held << klass if index < 10
  end
  [watched, held]
end.resume

if mode == 'replace'
  Fiber.new { sites.each { |site| raise 'bad replacement dispatch' unless site.call(held.first.new('x')) == 120 } }.resume
elsif mode == 'release'
  sites = nil
end
GC.start(full_mark: true, immediate_sweep: true)
remaining = watched.keys
puts "mode=#{mode} sites=#{count} remaining=#{remaining.size} indices=#{watched.values.sort.inspect}"
raise 'held classes lost' unless held.all? { |klass| remaining.include?(klass) }
raise 'unreachable classes retained' unless remaining.size == held.size
