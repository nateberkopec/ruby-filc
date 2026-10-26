Warning[:experimental] = false
buffer = IO::Buffer.new(IO::Buffer::PAGE_SIZE, IO::Buffer::MAPPED | IO::Buffer::SHARED)
buffer.set_string('old!')
ready_r, ready_w = IO.pipe
result_r, result_w = IO.pipe
pid = fork do
  ready_w.close
  result_r.close
  ready_r.read(1)
  result_w.write(buffer.get_string(0, 4))
  result_w.close
end
ready_r.close
result_w.close
buffer.resize(4)
buffer.set_string('new!')
ready_w.write('x')
ready_w.close
observed = result_r.read
Process.wait(pid)
puts "mapped=#{buffer.mapped?} shared=#{buffer.shared?} child=#{observed.inspect}"
raise 'resize lost shared mapping' unless observed == 'new!'
