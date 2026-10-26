events = []
klass = Class.new do
  define_singleton_method(:method_added) do |name|
    events << [:added, name]
    GC.start(full_mark: true, immediate_sweep: true)
  end
  define_singleton_method(:method_undefined) do |name|
    events << [:undefined, name]
    GC.start(full_mark: true, immediate_sweep: true)
  end
  def original
    :original
  end
  alias copied original
  undef original
end
raise 'alias changed' unless klass.new.copied == :original
raise 'undef failed' if klass.new.respond_to?(:original)
raise "incorrect callbacks #{events.inspect}" unless events == [[:added, :original], [:added, :copied], [:undefined, :original]]
puts 'alias and undef callbacks preserve rewound frames'
