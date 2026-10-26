$stdout.sync = true

mode = ARGV.fetch(0)
raise ArgumentError, mode unless %w[baseline dispatch].include?(mode)

def populate(mode)
  watched = ObjectSpace::WeakMap.new
  keep = []
  500.times do |i|
    klass = Class.new(String)
    if mode == 'dispatch'
      value = klass.new('x')
      raise 'dispatch returned incorrect data' unless value.getbyte(0) == 120
    end
    watched[klass] = true
    keep << klass if i < 10
  end
  [watched, keep]
end

watched, keep = Fiber.new { populate(mode) }.resume
GC.start(full_mark: true, immediate_sweep: true)
remaining = watched.keys
puts RUBY_DESCRIPTION
puts "mode=#{mode} created=500 held=#{keep.size} remaining=#{remaining.size}"
raise 'live classes disappeared' unless keep.all? { |klass| remaining.include?(klass) }
raise 'unreachable classes retained' unless remaining.size == keep.size
puts 'all held classes survived and all unreachable classes were collected'
