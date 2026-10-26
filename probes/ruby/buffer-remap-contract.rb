Warning[:experimental] = false
page = IO::Buffer::PAGE_SIZE
[IO::Buffer::MAPPED, IO::Buffer::MAPPED | IO::Buffer::PRIVATE].each do |flags|
  buffer = IO::Buffer.new(page * 2, flags)
  buffer.set_string('test')
  buffer.resize(2)
  raise 'mapped type lost' unless buffer.mapped?
  buffer.resize(page * 3)
  raise 'mapped type lost after growth' unless buffer.mapped?
  raise 'contents or zero-fill wrong' unless buffer.get_string == "te" + "\0" * (page * 3 - 2)
  raise 'private flag lost' if flags & IO::Buffer::PRIVATE != 0 && !buffer.private?
  buffer.free
end

buffer = IO::Buffer.new(page * 2, IO::Buffer::MAPPED | IO::Buffer::SHARED)
ready_r, ready_w = IO.pipe
result_r, result_w = IO.pipe
pid = fork do
  ready_w.close
  result_r.close
  ready_r.read(1)
  result_w.write(buffer.get_string(0, 4))
  result_w.close
  ready_r.close
  buffer.free
end
ready_r.close
result_w.close
buffer.resize(page)
buffer.resize(page * 2)
buffer.set_string('new!')
raise 'shared type lost' unless buffer.mapped? && buffer.shared?
ready_w.write('x')
ready_w.close
observed = result_r.read
result_r.close
Process.wait(pid)
raise 'child failed' unless $?.success?
raise 'shared contents lost' unless observed == 'new!'
buffer.free
puts 'private resize, zero-fill, shared shrink/regrowth and fork visibility passed'
