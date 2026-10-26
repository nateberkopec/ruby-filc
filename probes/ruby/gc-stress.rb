begin
  GC.stress = true
  before = GC.count
  10.times { Object.new }
  after = GC.count
ensure
  GC.stress = false
end
raise "stress did not collect on allocations: #{after - before}" unless after - before >= 10
puts "stress collections=#{after - before}"
