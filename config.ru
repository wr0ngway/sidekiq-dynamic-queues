#!/usr/bin/env ruby
require 'logger'

$LOAD_PATH.unshift ::File.expand_path(::File.dirname(__FILE__) + '/lib')
require 'sidekiq/web'
require 'sidekiq-dynamic-queues-server'

use Rack::ShowExceptions
run Sidekiq::Web
