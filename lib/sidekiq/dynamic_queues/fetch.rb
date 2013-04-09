require 'sidekiq/fetch'

module Sidekiq
  module DynamicQueues

    # enable with Sidekiq.options[:fetch] = Sidekiq::DynamicQueues::Fetch
    class Fetch < Sidekiq::BasicFetch

      include Sidekiq::Util
      include Sidekiq::DynamicQueues::Attributes
      
      def initialize(options)
        super
        @dynamic_queues = self.class.translate_from_cli(*options[:queues])
      end
  
      # overriding Sidekiq::BasicFetch#queues_cmd
      def queues_cmd
        if @dynamic_queues.grep(/(^!)|(^@)|(\*)/).size == 0
          super
        else
          queues = expanded_queues
          queues = @strictly_ordered_queues ? queues : queues.shuffle
          queues << Sidekiq::Fetcher::TIMEOUT
        end
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
      def expanded_queues
        queue_names = @dynamic_queues.dup

        real_queues = Sidekiq::Client.registered_queues
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
            matched_queues.concat(matches)
          end
        end

        return matched_queues.collect { |q| "queue:#{q}" }.uniq.sort
      end

      
      def self.translate_from_cli(*queues)
        queues.collect do |queue|
          queue.gsub('.star.', '*').gsub('.at.', '@').gsub('.not.', '!')
        end
      end
      
    end
    
  end
end
