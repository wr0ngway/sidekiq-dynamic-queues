require 'sidekiq'
require 'sidekiq/dynamic_queues/attributes'

module Sidekiq
  module DynamicQueues
    autoload :Fetch, 'sidekiq/dynamic_queues/fetch'
  end
end