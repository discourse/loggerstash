# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name = "loggerstash"

  s.version = "1.0.1"
  s.platform = Gem::Platform::RUBY

  s.summary  = "Monkeypatch Logger to send log entries to logstash"
  s.description = <<~EOF
    Provides a module you can prepend into any instance of Logger to cause
    it to send all logged entries to a Logstash server, in addition to
    however the message would have been handled otherwise.
  EOF

  s.authors  = ["Michael Brown"]
  s.email    = ["michael.brown@discourse.org"]
  s.homepage = "https://github.com/discourse/loggerstash"

  s.files = `git ls-files -z`.split("\0").reject { |f| f =~ /^(G|spec|Rakefile)/ }

  s.required_ruby_version = ">= 2.4.0"

  s.add_runtime_dependency "logstash_writer", ">= 0.0.11"

  s.add_development_dependency 'bundler'
  s.add_development_dependency 'guard-rspec'
  s.add_development_dependency 'guard-rubocop'
  s.add_development_dependency 'rack-test'
  s.add_development_dependency 'rake', "~> 12.0"
  s.add_development_dependency 'redcarpet'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'rubocop'
  s.add_development_dependency 'rubocop-discourse'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'yard'
end
