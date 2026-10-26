Signal.trap(:USR2) {}
STDERR.syswrite("before stress\n")
GC.stress = true
STDERR.syswrite("before fork\n")
pid = fork { STDERR.syswrite("child running\n") }
STDERR.syswrite("parent waiting\n")
Process.wait(pid)
GC.stress = false
STDERR.syswrite("status=#{$?.to_i}\n")
