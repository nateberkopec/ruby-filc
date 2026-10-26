require 'filc_vm_stack_heap'

$stdout.sync = true

def populate(depth, keys, addresses)
  return if depth.zero?
  object = 'x' * 65_536
  keys[object] = depth
  addresses << FilcVmStackHeap.address(object).to_s(16)
  populate(depth - 1, keys, addresses)
  nil
end

prefix = ARGV.fetch(0)
keys = ObjectSpace::WeakMap.new
addresses = []
fiber = Fiber.new do
  info = FilcVmStackHeap.stack_info
  populate(100, keys, addresses)
  Fiber.yield info
end
stack, size, frame = fiber.resume
puts "stack=#{stack.to_s(16)} bytes=#{size} frame=#{frame.to_s(16)} alive=#{fiber.alive?}"
GC.start(full_mark: true, immediate_sweep: true)
File.write("#{prefix}-targets.txt", addresses.join("\n"))
File.open("#{prefix}-heap.txt", 'w') { |file| FilcVmStackHeap.dump(file.fileno) }
puts "remaining=#{keys.keys.size} expected=0"
fiber.resume
