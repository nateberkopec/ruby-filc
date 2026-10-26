require 'filc_cache_heap'
require 'objspace'

$stdout.sync = true

def populate
  watched = ObjectSpace::WeakMap.new
  keep = []
  addresses = []
  500.times do |i|
    klass = Class.new(String)
    value = klass.new('x')
    raise unless value.getbyte(0) == 120
    watched[klass] = i
    keep << klass if i < 10
    addresses << FilcCacheHeap.address(klass).to_s(16) if i >= 10
  end
  [watched, keep, addresses]
end

watched, keep, addresses = Thread.new { populate }.value
GC.start(full_mark: true, immediate_sweep: true)
File.write('/work/ta/callcache-heap-targets.txt', addresses.join("\n"))
File.open('/work/ta/callcache-heap.txt', 'w') { |file| FilcCacheHeap.dump(file.fileno) }
puts "remaining=#{watched.size} indices=#{watched.values.sort.inspect} held=#{keep.size}"
File.open('/work/ta/callcache-objects.jsonl', 'w') { |file| ObjectSpace.dump_all(output: file) }
