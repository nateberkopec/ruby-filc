# x86-64 guarantees SSE2. Do not initialize the table before checking startup.
require 'cpu_features'
raise 'CPU features were not initialized before extension loading' unless CPUFeatures.sse2?
3.times do
  raise 'CPU initialization changed SSE2 availability' unless CPUFeatures.initialize! && CPUFeatures.sse2?
end
puts 'x86-64 CPU features are initialized before extension loading; repeated initialization is stable'
