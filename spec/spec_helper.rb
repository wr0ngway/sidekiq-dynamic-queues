require 'rspec'
require 'sidekiq-dynamic-queues'

# No need to start redis when running in Travis
unless ENV['CI']

  begin
    Sidekiq.redis {|r| r.info }
  rescue Errno::ECONNREFUSED
    spec_dir = File.dirname(File.expand_path(__FILE__))
    REDIS_CMD = "redis-server #{spec_dir}/redis-test.conf"
    
    puts "Starting redis for testing at localhost..."
    puts `cd #{spec_dir}; #{REDIS_CMD}`
    
    # Schedule the redis server for shutdown when tests are all finished.
    at_exit do
      puts 'Stopping redis'
      pid = File.read("#{spec_dir}/redis.pid").to_i rescue nil
      system ("kill -9 #{pid}") if pid.to_i != 0
      File.delete("#{spec_dir}/redis.pid") rescue nil
      File.delete("#{spec_dir}/redis-server.log") rescue nil
      File.delete("#{spec_dir}/dump.rdb") rescue nil
    end
  end
  
end

def dump_redis
  result = {}
  Sidekiq.redis do |redis|
    result = {}
    redis.keys("*").each do |key|
      type = redis.type(key)
      result["#{key} (#{type})"] = case type
        when 'string' then redis.get(key)
        when 'list' then redis.lrange(key, 0, -1)
        when 'zset' then redis.zrange(key, 0, -1, :with_scores => true)
        when 'set' then redis.smembers(key)
        when 'hash' then redis.hgetall(key)
        else type
      end
    end
  end
  return result
end

require 'sidekiq'
require 'celluloid'
require 'sidekiq/cli'
require 'sidekiq/manager'

Sidekiq.configure_client do |config|
  config.redis = { :namespace => 'sidekiq',
                   :size => 1,
                   :url => 'redis://localhost:6379/1' }
end

Sidekiq.configure_server do |config|
  config.redis = { :namespace => 'sidekiq',
                   :url => 'redis://localhost:6379/1' }
end

Celluloid.logger = nil
Sidekiq.logger = nil
#Celluloid.logger = Sidekiq.logger

def enqueue_on(queue, job_class, *job_args)
  job_class.client_push('class' => job_class, 'args' => job_args, 'queue' => queue)
end

def run_queues(*queues)
  options = queues.last.is_a?(Hash) ? queues.pop : {}
  options = {:async => false, :job_count => 1}.merge(options)
  
  Sidekiq::Fetcher.instance_eval { @done = false }
  manager = Sidekiq::Manager.new({:queues=>queues, :concurrency=>1, :timeout=>1})

  job_count = 0
  manager.when_done do
    job_count += 1
    yield if block_given?
    if job_count >= options[:job_count].to_i
      manager.stop(:shutdown => true, :timeout => 0)
    end
  end
  manager.start
  
  manager.wait(:shutdown) unless options[:async]
  manager
end


class SomeJob
  include Sidekiq::Worker
  
  class_attribute :result
  
  def perform(*args)
    self.class.result = args
  end
end
