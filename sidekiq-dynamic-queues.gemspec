
# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require 'sidekiq/dynamic_queues/version'

Gem::Specification.new do |s|
  s.name        = "sidekiq-dynamic-queues"
  s.version     = Sidekiq::DynamicQueues::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Matt Conway"]
  s.email       = ["matt@conwaysplace.com"]
  s.homepage    = ""
  s.summary     = %q{A sidekiq plugin for specifying the queues a worker pulls from with wildcards, negations, or dynamic look up from redis}
  s.description = %q{A sidekiq plugin for specifying the queues a worker pulls from with wildcards, negations, or dynamic look up from redis}

  s.rubyforge_project = "sidekiq-dynamic-queues"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency("sidekiq", '>= 3')

  s.add_development_dependency('rake')
  s.add_development_dependency('rspec', '~> 2.5')
  s.add_development_dependency('sinatra')
  s.add_development_dependency('slim')
  s.add_development_dependency('rack-test', '~> 0.5.4')
  s.add_development_dependency('tilt', '~> 1.4')

end

