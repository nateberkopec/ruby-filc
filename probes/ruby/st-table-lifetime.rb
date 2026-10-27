require 'st_table_lifetime'

operations = %w[delete shift update_delete delete_if clear]
if ARGV.empty?
  require 'open3'
  require 'rbconfig'
  operations.product([2, 8, 9, 100], %w[partial empty]).each do |operation, count, extent|
    next if operation == 'clear' && extent == 'partial'
    args = [operation, count.to_s, extent]
    output, status = Open3.capture2e(RbConfig.ruby, '-I', $LOAD_PATH.join(File::PATH_SEPARATOR), __FILE__, *args)
    raise "#{args.join(' ')}: #{output}" unless status.success?
    puts output
  end
  exit
end

operation, count, extent = ARGV
count = Integer(count)
raise 'invalid operation' unless operations.include?(operation)
raise 'invalid count' unless [2, 8, 9, 100].include?(count)
raise 'invalid extent' unless %w[partial empty].include?(extent)
raise 'clear cannot retain a subset' if operation == 'clear' && extent != 'empty'

keep = extent == 'empty' ? 0 : count / 2
indices = operation == 'shift' ? (count - keep...count).to_a : (0...keep).to_a
expected = indices.flat_map { |index| [[index, :key], [index, :value]] }
weak = ObjectSpace::WeakMap.new
held = nil
Thread.new do
  held = NativeLifetimeTable.new
  count.times do |index|
    key, value = Object.new, Object.new
    key.instance_variable_set(:@tag, [index, :key])
    value.instance_variable_set(:@tag, [index, :value])
    weak[key] = weak[value] = true
    held[key] = value
  end
  case operation
  when 'delete', 'update_delete'
    held.to_a.each do |key, value|
      next if key.instance_variable_get(:@tag).first < keep
      result = held.public_send(operation, key)
      raise 'wrong delete return' unless operation == 'delete' ? result.equal?(value) : result == true
    end
  when 'shift'
    (count - keep).times do |index|
      raise 'wrong shift return' unless held.shift.map { |object| object.instance_variable_get(:@tag) } == [[index, :key], [index, :value]]
    end
  when 'delete_if'
    held.delete_if { |key, value| key.instance_variable_get(:@tag).first >= keep }
  when 'clear'
    raise 'wrong clear return' unless held.clear.equal?(held)
  end
  nil
end.join

3.times { GC.start(full_mark: true, immediate_sweep: true) }
live = []
weak.each_key { |object| live << object.instance_variable_get(:@tag) }
raise "unexpected live markers: #{live.sort.inspect}; expected #{expected.inspect}" unless live.sort == expected.sort
pairs = held.to_a.flat_map { |pair| pair.map { |object| object.instance_variable_get(:@tag) } }
raise 'lost entries or order' unless pairs == expected
held[:reused] = :yes
raise 'cannot reuse table' unless held.to_a.last == [:reused, :yes] && held.to_a.size == keep + 1
puts "st_table #{operation} #{count} #{extent}: removed keys/values collected; survivors, order and reuse preserved"
