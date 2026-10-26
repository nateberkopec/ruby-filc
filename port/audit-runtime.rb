require 'fiddle'
require 'json'
require 'open3'
require 'openssl'
require 'psych'
require 'zlib'

paths = %w[/opt /usr].flat_map { |root| Dir.glob("#{root}/**/*", File::FNM_DOTMATCH) }
musl_paths = paths.grep(/musl/i)
musl_headers = musl_paths.select { |path| path.start_with?('/opt/fil/include/c++/') && path.end_with?('/locale_base_api/musl.h') }
raise "unclassified musl paths: #{musl_paths.inspect}" unless musl_paths == musl_headers
packages, status = Open3.capture2('dpkg-query', '-W', '-f=${binary:Package}\n')
raise 'dpkg-query failed' unless status.success?
raise 'musl package installed' if packages.match?(/musl/i)

interpreters = Hash.new(0)
static_executables = []
elf_count = 0
paths.each do |path|
  next unless File.file?(path) && !File.symlink?(path)
  File.open(path, 'rb') do |file|
    header = file.read(64)
    next unless header&.start_with?("\x7fELF")
    raise "unsupported ELF layout: #{path}" unless header.getbyte(4) == 2 && header.getbyte(5) == 1
    elf_count += 1
    offset = header.byteslice(32, 8).unpack1('Q<')
    size, count = header.byteslice(54, 4).unpack('S<2')
    interpreter = nil
    count.times do |index|
      file.seek(offset + index * size)
      entry = file.read(size)
      next unless entry.unpack1('L<') == 3
      file.seek(entry.byteslice(8, 8).unpack1('Q<'))
      interpreter = file.read(entry.byteslice(32, 8).unpack1('Q<')).delete_suffix("\0")
      interpreters[interpreter] += 1
    end
    static_executables << path if !interpreter && header.byteslice(16, 2).unpack1('S<') == 2
  end
end
raise "unexpected ELF interpreters: #{interpreters.keys.inspect}" unless interpreters.keys.all? { |path| File.basename(path).start_with?('ld-linux-', 'ld-fil1-') }
raise "static executables need inspection: #{static_executables.inspect}" unless static_executables.empty?

archives = paths.select { |path| File.basename(path) == 'libc.a' && !File.symlink?(path) }
archives.each do |path|
  symbols, status = Open3.capture2e('nm', '-g', '--defined-only', path)
  raise "unidentified libc archive: #{path}" unless status.success? && symbols.include?('gnu_get_libc_version')
end
version = Fiddle::Function.new(Fiddle::Handle::DEFAULT['gnu_get_libc_version'], [], Fiddle::TYPE_VOIDP).call.to_s
maps = File.read('/proc/self/maps').lines.filter_map { |line| line.split.last if line.include?('.so') }.uniq
raise 'musl library loaded' if maps.any? { |path| path.match?(/musl/i) }
puts JSON.pretty_generate(ruby: RUBY_DESCRIPTION, glibc: version, elf_files: elf_count, interpreters: interpreters, libc_archives: archives, loaded_libraries: maps, musl_compatibility_headers: musl_headers)
