# Fixed-work interpreter kernels for instruction-count comparisons.
# Usage: ruby interpreter-overhead.rb CASE
# The "empty" case measures startup so drivers can subtract it.

def fib(n) = n < 2 ? n : fib(n - 1) + fib(n - 2)

CASES = {
  'empty' => -> {},
  'while' => -> { i = 0; while i < 10_000_000; i += 1; end },
  'fib' => -> { fib(27) },
  'attr' => -> { o = Struct.new(:a).new(0); 1_000_000.times { o.a += 1 } },
  'array-alloc' => -> { 1_000_000.times { [1, 2, 3] } },
  'string-alloc' => -> { 500_000.times { |i| "abc#{i}" } },
  'hash-lookup' => -> { h = { a: 1, b: 2, 'c' => 3 }; 1_000_000.times { h[:a]; h['c'] } },
}.freeze

name = ARGV.fetch(0)
CASES.fetch(name).call
