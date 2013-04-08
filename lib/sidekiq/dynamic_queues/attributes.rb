module Sidekiq
  module DynamicQueues

    DYNAMIC_QUEUE_KEY = "dynamic_queue"
    FALLBACK_KEY = "default"

    module Attributes
      extend self

      def json_encode(data)
        Sidekiq.dump_json(data)
      end
      
      def json_decode(data)
        return nil unless data
        Sidekiq.load_json(data)
      end
      
      def get_dynamic_queue(key, fallback=['*'])
        data = Sidekiq.redis {|r| r.hget(DYNAMIC_QUEUE_KEY, key) }
        queue_names = json_decode(data)

        if queue_names.nil? || queue_names.size == 0
          data = Sidekiq.redis {|r| r.hget(DYNAMIC_QUEUE_KEY, FALLBACK_KEY) }
          queue_names = json_decode(data)
        end
        
        if queue_names.nil? || queue_names.size == 0
          queue_names = fallback
        end

        return queue_names
      end

      def set_dynamic_queue(key, values)
        if values.nil? or values.size == 0
          Sidekiq.redis {|r| r.hdel(DYNAMIC_QUEUE_KEY, key) }
        else
          Sidekiq.redis {|r| r.hset(DYNAMIC_QUEUE_KEY, key, json_encode(values)) }
        end
      end
      
      def set_dynamic_queues(dynamic_queues)
        Sidekiq.redis do |r|
          r.multi do
            r.del(DYNAMIC_QUEUE_KEY)
            dynamic_queues.each do |k, v|
              set_dynamic_queue(k, v)
            end
          end
        end
      end

      def get_dynamic_queues
        result = {}
        queues = Sidekiq.redis {|r| r.hgetall(DYNAMIC_QUEUE_KEY) }
        queues.each {|k, v| result[k] = json_decode(v) }
        result[FALLBACK_KEY] ||= ['*']
        return result
      end

    end
    
  end
end
