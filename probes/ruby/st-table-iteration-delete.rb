require 'st_table_lifetime'

# Two entries leave capacity for reinsertion without a table rebuild. A rebuild
# can legitimately change traversal, so it is not part of this regression.
table = NativeLifetimeTable.new
keys = Array.new(2) { Object.new }
keys.each_with_index { |key, index| table[key] = index }
visited = []
table.delete_if do |key, value|
  raise 'visited a reinserted key twice' if visited.include?(key)
  visited << key
  raise 'wrong value' unless value == keys.index(key)
  table.delete(key)
  table[key] = value
  true
end
raise 'wrong traversal' unless visited == keys
raise 'reinserted entries survived ST_DELETE' unless table.to_a.empty?
puts 'st_table: ST_DELETE removes the reinserted current entry exactly once'
