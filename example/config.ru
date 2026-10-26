require "json"

run ->(_env) {
  body = JSON.generate(ruby: RUBY_DESCRIPTION, compiler: RbConfig::CONFIG.fetch("CC"))
  [200, {"content-type" => "application/json"}, [body]]
}
