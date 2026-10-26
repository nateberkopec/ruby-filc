require 'fiddle'
$stdout.sync = true
case ARGV.fetch(0)
when 'call'
  strlen = Fiddle::Function.new(Fiddle::Handle::DEFAULT['strlen'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_SIZE_T)
  raise unless strlen.call('abc') == 3
when 'pointer'
  pointer = Fiddle::Pointer['abc']
  raise unless Fiddle::Pointer.new(pointer.to_i).to_s(3) == 'abc'
when 'object'
  object = Object.new
  raise unless Fiddle.dlunwrap(Fiddle.dlwrap(object)).equal?(object)
end
puts 'ok'
