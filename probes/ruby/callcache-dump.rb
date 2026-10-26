require 'json'
require 'objspace'

def dispatch(receiver)
  receiver.getbyte(0)
end

klass = Class.new(String)
receiver = klass.new('x')
raise unless dispatch(receiver) == 120
expected = JSON.parse(ObjectSpace.dump(klass)).fetch('address')
previously_disabled = GC.disable
begin
  rows = ObjectSpace.dump_all(output: :string).lines.map { |line| JSON.parse(line) }
  caches = rows.select { |row| row['imemo_type'] == 'callcache' && row['called_id'] == 'getbyte' }
  raise 'call cache not observed' if caches.empty?
  raise 'receiver_class is not the receiver class address' unless caches.any? { |row| row['receiver_class'] == expected }
  classes = rows.select { |row| %w[CLASS ICLASS].include?(row['type']) }.to_h { |row| [row['address'], true] }
  invalid = rows.count { |row| row.key?('receiver_class') && !classes.key?(row['receiver_class']) }
  raise "#{invalid} receiver_class references do not name classes" unless invalid.zero?
  puts 'callcache receiver_class fields resolve to Ruby classes'
ensure
  GC.enable unless previously_disabled
end
