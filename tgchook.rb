require '-test-/tracepoint'
$stdout.sync = true
GC.disable
puts :disabled
GC.stat({})
Bug.tracepoint_track_objspace_events do
  GC.enable
  puts :enabled
  1_000_000.times { '' }
  puts :allocated
  GC.disable
  puts :disabled_again
end
puts :unhooked
GC.stat({})
GC.enable
puts :done
