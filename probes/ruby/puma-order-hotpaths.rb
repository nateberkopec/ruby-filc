# Diagnostic only: this omits Puma and HTTP and is not an acceptance workload.
require 'digest'
require 'json'

iterations = Integer(ARGV.fetch(0, '10000'))
raise 'iterations must be positive' unless iterations.positive?
phase = ARGV.fetch(1, 'all')
phases = %w[parse transform digest generate all]
raise "unknown phase #{phase}; use #{phases.join(', ')}" unless phases.include?(phase)

input = {
  'id' => 'diagnostic-order',
  'items' => Array.new(50) { |index| { 'sku' => "item-#{index}", 'price' => index + 1, 'quantity' => 3 } },
  'note' => 'order details ' * 256
}
body = JSON.generate(input)
expected = {
  'id' => input.fetch('id'),
  'items' => Array.new(50) { |index| { 'sku' => "item-#{index}", 'total' => (index + 1) * 3 } },
  'total' => 3825,
  'digest' => Digest::SHA256.hexdigest(input.fetch('note'))
}
encoded = JSON.generate(expected)
operation, reference = case phase
when 'parse'
  [-> { JSON.parse(body) }, input]
when 'transform'
  [-> {
    items = input.fetch('items').map do |item|
      { 'sku' => item.fetch('sku'), 'total' => item.fetch('price') * item.fetch('quantity') }
    end
    [items, items.sum { |item| item.fetch('total') }]
  }, [expected.fetch('items'), expected.fetch('total')]]
when 'digest'
  [-> { Digest::SHA256.hexdigest(input.fetch('note')) }, expected.fetch('digest')]
when 'generate'
  [-> { JSON.generate(expected) }, encoded]
when 'all'
  [-> {
    parsed = JSON.parse(body)
    items = parsed.fetch('items').map do |item|
      { 'sku' => item.fetch('sku'), 'total' => item.fetch('price') * item.fetch('quantity') }
    end
    JSON.generate({ 'id' => parsed.fetch('id'), 'items' => items,
                    'total' => items.sum { |item| item.fetch('total') },
                    'digest' => Digest::SHA256.hexdigest(parsed.fetch('note')) })
  }, encoded]
end

100.times { raise 'incorrect warmup result' unless operation.call == reference }
allocated = GC.stat(:total_allocated_objects)
started_cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
iterations.times do
  raise 'incorrect diagnostic result' unless operation.call == reference
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - started_cpu
puts JSON.generate(ruby: RUBY_DESCRIPTION, phase: phase, iterations: iterations,
                   elapsed_seconds: elapsed, process_cpu_seconds: cpu,
                   iterations_per_second: iterations / elapsed,
                   allocated_objects: GC.stat(:total_allocated_objects) - allocated,
                   diagnostic_only: true)
