require 'nio'
require 'socket'

%i[epoll poll select].each do |backend|
  selector = NIO::Selector.new(backend)
  reader, writer = Socket.pair(:UNIX, :STREAM)
  monitor = selector.register(reader, :r)
  monitor.value = Object.new
  monitor.add_interest(:w)
  raise 'add_interest' unless monitor.interests == :rw
  monitor.remove_interest(:w)
  raise 'remove_interest' unless monitor.interests == :r
  100.times do
    writer.write('x')
    GC.start
    ready = selector.select(1)
    raise 'readiness' unless ready == [monitor] && monitor.readable?
    raise 'data' unless reader.read(1) == 'x'
  end
  raise 'deregister' unless selector.deregister(reader) == monitor
  selector.close
  reader.close
  writer.close
  puts "#{backend}: 100 readable events, interest changes and GC passed"
end
