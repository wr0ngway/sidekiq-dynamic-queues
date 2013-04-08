require 'sidekiq-dynamic-queues'
require 'sidekiq/web'
require 'sidekiq/dynamic_queues/server'

Sidekiq::Web.register Sidekiq::DynamicQueues::Server
