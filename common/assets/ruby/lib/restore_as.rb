# frozen_string_literal: true

limit = ENV.delete("UBICLOUD_RUBY_AS_LIMIT")
limit = (limit == "unlimited") ? Process::RLIM_INFINITY : Integer(limit, 10) * 1024
Process.setrlimit(:AS, limit, Process.getrlimit(:AS)[1])
