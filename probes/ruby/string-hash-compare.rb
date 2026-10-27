require 'string_hash_compare'

checks = 0
encodings = [Encoding::BINARY, Encoding::UTF_8, Encoding::US_ASCII,
             Encoding::UTF_16LE, Encoding::UTF_16BE]
((0..40).to_a + [63, 64, 65, 127, 128]).each do |length|
  bytes = Array.new(length) { |index| (index * 37) % 256 }.pack('C*')
  variants = [bytes.dup, bytes + "\0", bytes.byteslice(0, [length - 1, 0].max)]
  length.times do |index|
    changed = bytes.dup
    changed.setbyte(index, changed.getbyte(index) ^ 0x80)
    variants << changed
  end
  # Frozen/shared and mutable inputs, including embedded NULs and invalid byte
  # sequences, must preserve String#eql?'s encoding compatibility rules.
  [bytes, (bytes * 20).freeze.byteslice(0, length), bytes.dup.freeze].each do |left|
    variants.each do |right|
      encodings.product(encodings).each do |left_encoding, right_encoding|
        a = left.dup.force_encoding(left_encoding)
        b = right.dup.force_encoding(right_encoding)
        a.freeze if left.frozen?
        expected = a.eql?(b)
        actual = StringHashCompare.equal?(a, b)
        raise "comparison mismatch at length #{length}, #{left_encoding}/#{right_encoding}" unless actual == expected
        checks += 1
      end
    end
  end
  key = bytes.dup.freeze
  hash = {key => :found}
  raise "lookup failed at length #{length}" unless hash.fetch(bytes.dup) == :found
end
puts "String hash comparison: #{checks} length/content/encoding checks passed"
