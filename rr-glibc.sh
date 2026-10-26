#!/bin/bash
docker exec -i ruby-filc-glibc bash -lc "cd /work/ruby-4.0.7-glibc && ./miniruby tool/runruby.rb --archdir=. --extout=.ext -- $*" 2>&1
