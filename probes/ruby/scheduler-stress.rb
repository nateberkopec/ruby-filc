require '/work/ruby-4.0.7-glibc/test/fiber/scheduler'
$stdout.sync = true
Signal.trap(:USR2) {}
File.write('/work/ta/scheduler-stress.pid', Process.pid.to_s)
Thread.new do
  Fiber.set_scheduler(Scheduler.new)
  Fiber.schedule do
    puts 'stress on'
    GC.stress = true
    puts 'compile'
    RubyVM::InstructionSequence.compile_file(File::NULL)
    puts 'compiled'
    GC.stress = false
  end
end.join
puts 'done'
