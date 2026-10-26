$stdout.sync = true
GC.start
before = GC.stat
raise 'missing live count' unless before[:heap_live_slots].is_a?(Integer)
raise 'missing heap statistics' unless GC.stat_heap.is_a?(Hash)
GC.disable
objects = Array.new(20_000) { Object.new }
during = GC.stat
raise 'untracked allocations' unless during[:total_allocated_objects] - before[:total_allocated_objects] >= 20_000
raise 'untracked live objects' unless during[:heap_live_slots] - before[:heap_live_slots] >= 20_000
raise 'objects disappeared' unless objects.size == 20_000
objects = nil
GC.enable
3.times { GC.start }
after = GC.stat
raise 'untracked collections' unless after[:total_freed_objects] - during[:total_freed_objects] >= 20_000
GC.disable
heaps = GC.stat_heap
heaps.each do |id, stats|
  raise 'bad slot size' unless stats[:slot_size] == GC.stat_heap(id, :slot_size)
  raise 'bad live count' unless stats[:heap_live_slots] >= 0
  raise 'bad allocation count' unless stats[:total_allocated_objects] >= stats[:total_freed_objects]
end
[-1, heaps.size].each do |id|
  begin
    GC.stat_heap(id)
  rescue ArgumentError
    next
  end
  raise 'accepted invalid heap index'
end
GC.enable
puts "allocated=#{during[:total_allocated_objects] - before[:total_allocated_objects]} collected=#{after[:total_freed_objects] - during[:total_freed_objects]} heaps=#{heaps.keys.inspect}"
