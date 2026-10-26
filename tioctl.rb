reader, writer = IO.pipe
writer.write('abc')
buffer = +''
reader.ioctl(0x541b, buffer)
raise buffer.inspect unless buffer.unpack1('i') == 3
writer.close
reader.close
puts 'FIONREAD=3'
