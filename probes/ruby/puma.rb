require 'digest'
require 'net/http'
require 'puma'

tls = ARGV == ['--tls']
raise 'usage: puma.rb [--tls]' unless ARGV.empty? || tls
if tls
  require 'openssl'
  key = OpenSSL::PKey::RSA.generate(2048)
  cert = OpenSSL::X509::Certificate.new
  cert.version = 2
  cert.serial = 1
  cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=Puma local test')
  cert.public_key = key.public_key
  cert.not_before = Time.now - 60
  cert.not_after = Time.now + 3600
  extensions = OpenSSL::X509::ExtensionFactory.new(cert, cert)
  cert.add_extension(extensions.create_extension('basicConstraints', 'CA:TRUE', true))
  cert.add_extension(extensions.create_extension('subjectAltName', 'IP:127.0.0.1'))
  cert.sign(key, OpenSSL::Digest.new('SHA256'))
  store = OpenSSL::X509::Store.new
  store.add_cert(cert)
  context = Puma::MiniSSL::Context.new
  context.key_pem = key.to_pem
  context.cert_pem = cert.to_pem
end

app = lambda do |env|
  body = env.fetch('rack.input').read
  GC.start
  [200, { 'content-type' => 'text/plain' }, ["#{env.fetch('PATH_INFO')}\n#{Digest::SHA256.hexdigest(body)}"]]
end
server = Puma::Server.new(app, nil, min_threads: 1, max_threads: 5)
if tls
  server.add_ssl_listener('127.0.0.1', 0, context)
else
  server.add_tcp_listener('127.0.0.1', 0)
end
port = server.connected_ports.fetch(0)
server.run
begin
  if tls
    # A trusted certificate with the wrong hostname and an untrusted
    # certificate must both be rejected, not merely encrypt the connection.
    [['wrong.invalid', store, /hostname mismatch/],
     ['127.0.0.1', OpenSSL::X509::Store.new, /self.signed certificate/]].each do |host, trust, reason|
      config = OpenSSL::SSL::SSLContext.new
      config.verify_mode = OpenSSL::SSL::VERIFY_PEER
      config.verify_hostname = true
      config.cert_store = trust
      socket = OpenSSL::SSL::SSLSocket.new(TCPSocket.new('127.0.0.1', port), config)
      socket.sync_close = true
      socket.hostname = host
      begin
        socket.connect
        raise 'invalid TLS peer was accepted'
      rescue OpenSSL::SSL::SSLError => error
        raise unless reason.match?(error.message)
      ensure
        socket.close
      end
    end
  end
  Array.new(5) do |client|
    Thread.new do
      options = { open_timeout: 3, read_timeout: 10 }
      options.merge!(use_ssl: true, cert_store: store, verify_mode: OpenSSL::SSL::VERIFY_PEER) if tls
      Net::HTTP.start('127.0.0.1', port, nil, **options) do |http|
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
puts "Puma #{Puma::Const::PUMA_VERSION}: 100 #{tls ? 'HTTPS' : 'HTTP'} POSTs across 5 concurrent keep-alive clients with forced GC passed"
