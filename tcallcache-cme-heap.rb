require 'filc_cache_heap'
require 'objspace'

$stdout.sync = true
sites = Array.new(8) { eval('->(value) { value.cached_byte }') }
watched, held, addresses = Fiber.new do
  watched = ObjectSpace::WeakMap.new
  held = []
  addresses = []
  500.times do |index|
    klass = Class.new(String) do
      def cached_byte
        getbyte(0)
      end
    end
    raise 'bad dispatch' unless sites[index % sites.size].call(klass.new('x')) == 120
    watched[klass] = index
    held << klass if index < 10
    addresses << FilcCacheHeap.address(klass).to_s(16) if index >= 10
  end
  [watched, held, addresses]
end.resume
GC.start(full_mark: true, immediate_sweep: true)
File.write('/work/ta/callcache-cme-heap-targets.txt', addresses.join("\n"))
File.open('/work/ta/callcache-cme-heap.txt', 'w') { |file| FilcCacheHeap.dump(file.fileno) }
File.open('/work/ta/callcache-cme-objects.jsonl', 'w') { |file| ObjectSpace.dump_all(output: file) }
puts "remaining=#{watched.size} indices=#{watched.values.sort.inspect} held=#{held.size} sites=#{sites.size}"
