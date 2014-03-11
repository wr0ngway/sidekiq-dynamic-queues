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

      # Returns a list of queues to use when searching for a job.
      #
      # A splat ("*") means you want every queue (in alpha order) - this
      # can be useful for dynamically adding new queues.
      #
      # The splat can also be used as a wildcard within a queue name,
      # e.g. "*high*", and negation can be indicated with a prefix of "!"
      #
      # An @key can be used to dynamically look up the queue list for key from redis.
      # If no key is supplied, it defaults to the worker's hostname, and wildcards
      # and negations can be used inside this dynamic queue list.   Set the queue
      # list for a key with
      # Sidekiq::DynamicQueues::Attributes.set_dynamic_queue(key, ["q1", "q2"]
      #
      def expand_queues(queues)
        queue_names = queues.dup

        real_queues = Sidekiq::Queue.all.map(&:name)
        matched_queues = []

        while q = queue_names.shift
          q = q.to_s

          if q =~ /^(!)?@(.*)/
            key = $2.strip
            key = hostname if key.size == 0

            add_queues = get_dynamic_queue(key)
            add_queues.map! { |q| q.gsub!(/^!/, '') || q.gsub!(/^/, '!') } if $1

            queue_names.concat(add_queues)
            next
          end

          if q =~ /^!/
            negated = true
            q = q[1..-1]
          end

          patstr = q.gsub(/\*/, ".*")
          pattern = /^#{patstr}$/
          if negated
            matched_queues -= matched_queues.grep(pattern)
          else
            matches = real_queues.grep(/^#{pattern}$/)
            matches = [q] if matches.size == 0 && q == patstr
            matched_queues.concat(matches.sort)
          end
        end

        return matched_queues.collect { |q| "queue:#{q}" }.uniq
      end

    end

  end
end
