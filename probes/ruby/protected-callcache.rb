class ProtectedCacheProbe
  attr_writer :token
  protected :token=

  def initialize
    @token = 7
  end

  def invoke(other)
    other.token = 9
    other.token
  end

  protected

  def token
    @token
  end
end

left = ProtectedCacheProbe.new
right = ProtectedCacheProbe.new
1_000.times { raise 'protected dispatch failed' unless left.invoke(right) == 9 }
begin
  GC.stress = true
  raise 'protected dispatch failed under GC stress' unless left.invoke(right) == 9
ensure
  GC.stress = false
end
begin
  right.token
  raise 'protected visibility was lost'
rescue NoMethodError
end
puts 'protected getter/setter dispatch, GC stress, and visibility passed'
