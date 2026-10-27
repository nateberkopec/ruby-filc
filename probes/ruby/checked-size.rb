require 'checked_size'

maximum = CheckedSize::MAX
values = [0, 1, 2, 3, maximum, maximum - 1]
[8, 16, 32, 63].each do |bits|
  pivot = 1 << bits
  values.concat([pivot - 1, pivot, pivot + 1]) if pivot < maximum
end
[2, 3, 7, CheckedSize::VALUE_BYTES, 65535].each do |factor|
  values.concat([maximum / factor, maximum / factor + 1])
end
values.uniq!
random = Random.new(1947)
pairs = values.product(values) + Array.new(10_000) do
  [random.rand(0..maximum), random.rand(0..maximum)]
end

checks = 0
verify = lambda do |operation, arguments, left, operator, right|
  expected = left.public_send(operator, right) # Arbitrary-precision reference.
  if expected > maximum
    begin
      CheckedSize.public_send(operation, *arguments)
    rescue ArgumentError => error
      message = "malloc: possible integer overflow (#{left}#{operator}#{right})"
      raise "wrong overflow error: #{error.message.inspect}" unless error.message == message
    else
      raise "overflow accepted: #{left}#{operator}#{right}"
    end
  else
    actual = CheckedSize.public_send(operation, *arguments)
    raise "wrong result: #{left}#{operator}#{right}=#{actual}" unless actual == expected
  end
  checks += 1
end

pairs.each do |left, right|
  verify.call(:multiply, [left, right], left, :*, right)
  verify.call(:add, [left, right], left, :+, right)
end
values.each do |value|
  verify.call(:bytes, [value], value, :*, 1)
  verify.call(:values, [value], value, :*, CheckedSize::VALUE_BYTES)
end
puts "checked size arithmetic: #{checks} boundary/random/constant-factor checks passed"
