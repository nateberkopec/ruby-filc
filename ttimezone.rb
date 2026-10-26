ENV['TZ'] = 'America/Managua'
t = Time.utc(1993, 1, 1, 6).localtime
puts t
abort "expected -0500, got #{t.utc_offset}" unless t.utc_offset == -18000
