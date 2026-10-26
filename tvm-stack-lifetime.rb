def populate(depth, keys)
  return if depth.zero?
  object = 'x' * 65_536
  keys[object] = depth
  populate(depth - 1, keys)
  nil
end

keys = ObjectSpace::WeakMap.new
fiber = Fiber.new do
  populate(100, keys)
  Fiber.yield :populated
end
raise unless fiber.resume == :populated && fiber.alive?
GC.start(full_mark: true, immediate_sweep: true)
remaining = keys.keys.size
puts "remaining=#{remaining} expected=0 alive=#{fiber.alive?}"
raise 'returned Ruby frames retain their local objects' unless remaining.zero?
fiber.resume
