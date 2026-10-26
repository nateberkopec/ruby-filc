def rss = File.read("/proc/self/status")[/VmRSS:\s+(\d+)/, 1].to_i / 1024
Q = Queue.new
def fz = proc { Q << 1 }
module M; def m = 1; end
r = 10.times.map do
  20000.times do
    c = Class.new; Class.new(c)
    o = Object.new; o.singleton_class.define_method(:x) { 1 }; o.extend(M)
  end
  3.times { GC.start }
  "#{rss}MB/fin=#{Q.size}"
end
puts "classes+singletons: #{r.join(' ')}"
p subclasses_ok: (k = Class.new; a = Class.new(k); b = Class.new(k); k.subclasses.sort_by(&:object_id) == [a, b].sort_by(&:object_id)), descendants: Object.subclasses.size > 10
