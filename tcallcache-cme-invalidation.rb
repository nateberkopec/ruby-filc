$stdout.sync = true
klass = Class.new
workers = Array.new(4) do
  Ractor.new(klass) do |type|
    object = type.new
    loop do
      expected = Ractor.receive
      break if expected.nil?
      if expected == :missing
        raise 'removed method remained visible' if object.respond_to?(:current)
        begin
          object.current
          raise 'removed method remained callable'
        rescue NoMethodError
        end
      else
        50.times do
          raise 'stale method entry' unless object.current == expected
          raise 'stale alias entry' unless object.snapshot == expected
        end
      end
      Ractor.main << expected
    end
    true
  end
end

25.times do |version|
  klass.class_eval("def current; #{version}; end; alias snapshot current")
  GC.start(full_mark: true, immediate_sweep: true)
  workers.each { |worker| worker << version }
  workers.size.times { raise 'wrong worker response' unless Ractor.receive == version }
  klass.class_eval { undef_method :current, :snapshot }
  GC.start(full_mark: true, immediate_sweep: true)
  workers.each { |worker| worker << :missing }
  workers.size.times { raise 'wrong missing-method response' unless Ractor.receive == :missing }
end
workers.each { |worker| worker << nil }
workers.each { |worker| raise 'worker failed' unless worker.value }
puts '25 redefinitions, aliases and removals passed across four Ractors with forced GC'
