require 'digest'
require 'net/http'
require 'puma'

app = lambda do |env|
  body = env.fetch('rack.input').read
  GC.start
  [200, { 'content-type' => 'text/plain' }, ["#{env.fetch('PATH_INFO')}\n#{Digest::SHA256.hexdigest(body)}"]]
end
server = Puma::Server.new(app, nil, min_threads: 1, max_threads: 5)
server.add_tcp_listener('127.0.0.1', 0)
port = server.connected_ports.fetch(0)
server.run
begin
  Array.new(5) do |client|
    Thread.new do
      Net::HTTP.start('127.0.0.1', port, nil, open_timeout: 3, read_timeout: 10) do |http|
        20.times do |request|
          path = "/client/#{client}/request/#{request}"
          body = "payload-#{client}-#{request}" * 1000
          response = http.post(path, body)
          expected = "#{path}\n#{Digest::SHA256.hexdigest(body)}"
          raise "bad response: #{response.code}" unless response.code == '200' && response.body == expected
        end
      end
    end
  end.each(&:value)
ensure
  server.stop(true)
end
3.times { GC.start }
puts "Puma #{Puma::Const::PUMA_VERSION}: 100 POSTs across 5 concurrent keep-alive clients with forced GC passed"
