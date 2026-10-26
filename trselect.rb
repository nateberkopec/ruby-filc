20.times do
  rs = 7.times.map { Ractor.new { 50.times { Encoding::Converter.asciicompat_encoding('I') } } }
  until rs.empty?
    r, = Ractor.select(*rs)
    rs.delete(r)
  end
end
puts 'Ractor.select passed'
