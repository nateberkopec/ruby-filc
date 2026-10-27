# Diagnostic only. Load the libraries to investigate with ruby -r before this
# script. Forced GC/scavenging and heap dumping are not acceptance measurements.
require 'filc_cache_heap'
require 'json'

prefix = ARGV.fetch(0)
3.times { GC.start(full_mark: true, immediate_sweep: true) }
FilcCacheHeap.scavenge
stats = GC.stat
status = File.read('/proc/self/status')
smaps = File.read('/proc/self/smaps')
File.write("#{prefix}.status", status)
File.write("#{prefix}.smaps", smaps)
File.open("#{prefix}.heap", 'w') { |file| FilcCacheHeap.dump(file.fileno) }
puts JSON.generate(ruby: RUBY_DESCRIPTION, pid: Process.pid, gc: stats,
                   loaded_features: $LOADED_FEATURES, diagnostic_only: true)
