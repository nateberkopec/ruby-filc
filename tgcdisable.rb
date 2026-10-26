$stdout.sync = true
puts :start
GC.disable
puts :disabled
GC.stat({})
GC.enable
puts :enabled
1_000_000.times { '' }
puts :allocated
GC.disable
puts :disabled_again
GC.stat({})
GC.enable
puts :done
