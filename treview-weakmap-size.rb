require 'objspace'

weak_map = ObjectSpace::WeakMap.new
weak_key_map = ObjectSpace::WeakKeyMap.new
keys = Array.new(100) { Object.new }
values = Array.new(100) { Object.new }
keys.each_with_index do |key, index|
  weak_map[key] = values[index]
  weak_key_map[key] = values[index]
end
sizes = [ObjectSpace.memsize_of(weak_map), ObjectSpace.memsize_of(weak_key_map)]
puts "sizes=#{sizes.inspect} entries=#{weak_map.size}"
expected_difference = 100 * 2 * [0].pack('J').bytesize
raise 'WeakMap entry fields are missing from accounting' unless sizes[0] - sizes[1] == expected_difference
