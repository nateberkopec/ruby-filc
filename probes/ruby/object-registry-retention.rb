# Intrusive Fil-C-only diagnostics. Never run inside acceptance measurements.
require 'filc_cache_heap'
require 'objspace'
require 'json'

CHAR = 'x'.freeze

sizes = GC.stat_heap.to_h { |id, stats| [stats.fetch(:slot_size), id] }
capacities = [0, 40, 100, 250, 550]
covered = []
cycles = []

3.times do |round|
  weak = ObjectSpace::WeakMap.new
  GC.disable
  count = GC.count
  # End the thread that inspects live objects before testing reclamation, so
  # native diagnostic stack references do not become roots in this test.
  Thread.new do
    capacities.each do |capacity|
      sample = CHAR * capacity
      dump = JSON.parse(ObjectSpace.dump(sample))
      raise 'test string is not embedded' unless dump.fetch('embedded')
      heap = sizes.fetch(dump.fetch('slot_size'))
      covered << heap
      before = GC.stat_heap(heap, :heap_live_slots)
      2_000.times do
        object = CHAR * capacity
        weak[object] = true
      end
      cycles << FilcCacheHeap.collect
      after = GC.stat_heap(heap, :heap_live_slots)
      raise "lost heap #{heap} allocations" unless after - before >= 2_000
      raise 'native collection changed logical GC count' unless GC.count == count
    end
    nil
  end.join
  raise "disabled GC lost roots: #{weak.size}" unless weak.size == 10_000

  # Explicit Ruby collection must release disabled-GC roots without changing
  # the logical state; finishing it must restore roots for surviving objects.
  3.times { GC.start(full_mark: true, immediate_sweep: true) }
  raise "explicit GC retained dead objects: #{weak.size}" unless weak.size.zero?
  raise 'explicit collection enabled GC' unless GC.disable

  Thread.new do
    10_000.times { weak[CHAR * 100] = true }
    nil
  end.join
  cycles << FilcCacheHeap.collect
  raise 'post-collection allocations were not retained' unless weak.size == 10_000
  raise 'GC state changed' unless GC.enable
  3.times { GC.start(full_mark: true, immediate_sweep: true) }
  raise "enable left retained roots: #{weak.size}" unless weak.size.zero?
  puts "round #{round + 1}: all size classes tracked, disabled roots retained, explicit/enable reclamation passed"
end
raise "missing heap classes: #{covered.uniq.inspect}" unless covered.uniq.sort == sizes.values.sort
raise 'native collections did not advance' unless cycles.each_cons(2).all? { |a, b| b > a }
