require 'digest'
require 'json'
require 'puma'
require 'rbconfig'

raise "expected Ruby 4.0.9, got #{RUBY_VERSION}" unless RUBY_VERSION == '4.0.9'
threads = Integer(ENV.fetch('PUMA_THREADS', '5'))
app = lambda do |env|
  case env.fetch('PATH_INFO')
  when '/health'
    [200, { 'content-type' => 'text/plain' }, ['ready']]
  when '/gc'
    GC.start(full_mark: true, immediate_sweep: true)
    [200, { 'content-type' => 'application/json' }, [JSON.generate(GC.stat)]]
  when '/orders'
    input = JSON.parse(env.fetch('rack.input').read)
    items = input.fetch('items').map do |item|
      { 'sku' => item.fetch('sku'), 'total' => item.fetch('price') * item.fetch('quantity') }
    end
    result = {
      'id' => input.fetch('id'),
      'items' => items,
      'total' => items.sum { |item| item.fetch('total') },
      'digest' => Digest::SHA256.hexdigest(input.fetch('note'))
    }
    [200, { 'content-type' => 'application/json' }, [JSON.generate(result)]]
  else
    [404, { 'content-type' => 'text/plain' }, ['not found']]
  end
end
server = Puma::Server.new(app, nil, min_threads: threads, max_threads: threads)
server.add_tcp_listener('127.0.0.1', Integer(ARGV.fetch(0)))
Signal.trap('TERM') { server.stop }
STDOUT.sync = true
puts JSON.generate(ruby: RUBY_DESCRIPTION, puma: Puma::Const::PUMA_VERSION,
                   nio4r: Gem.loaded_specs.fetch('nio4r').version.to_s,
                   compiler: RbConfig::CONFIG.fetch('CC'), pid: Process.pid, threads: threads,
                   yjit: defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : false,
                   zjit: defined?(RubyVM::ZJIT) ? RubyVM::ZJIT.enabled? : false)
server.run.join
