$stdout.sync = true

mode = ARGV.fetch(0)
raise ArgumentError, mode unless %w[baseline dispatch].include?(mode)

def populate(mode)
  watched = ObjectSpace::WeakMap.new
  keep = []
  500.times do |index|
    klass = Class.new(String) do
      def cached_byte
        getbyte(0)
      end
    end
    if mode == 'dispatch'
      value = klass.new('x')
      raise 'dispatch returned incorrect data' unless value.cached_byte == 120
    end
    watched[klass] = true
    keep << klass if index < 10
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
keep.each { |klass| raise 'held method entry lost' unless klass.new('x').cached_byte == 120 }
puts 'all held classes and methods survived and all unreachable classes were collected'
