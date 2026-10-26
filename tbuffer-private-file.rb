Warning[:experimental] = false
page = IO::Buffer::PAGE_SIZE
path = "/tmp/ruby-filc-private-#{$$}"
buffer = nil
begin
  File.open(path, 'w+') do |file|
    file.write('A' * (page * 2))
    file.flush
    buffer = IO::Buffer.map(file, page, 0, IO::Buffer::PRIVATE)
    buffer.resize(page * 2)
    file.pwrite('B', 0)
    observed = buffer.get_string(0, 1)
    puts "mapped=#{buffer.mapped?} private=#{buffer.private?} observed=#{observed.inspect}"
    raise 'private mapping lost its file association' unless observed == 'B'
  end
ensure
  buffer&.free
  File.unlink(path) if File.exist?(path)
end
