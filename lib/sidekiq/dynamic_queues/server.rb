require 'sidekiq-dynamic-queues'

module Sidekiq
  module DynamicQueues
    module Server

      Attr = Sidekiq::DynamicQueues::Attributes

      def self.registered(app)
        
        app.helpers do
          
          def find_template(view,*a,&b)
            dir = File.expand_path("../server/views/", __FILE__)
            super(dir,*a,&b)
            super
          end
          
        end
        
        app.get "/dynamicqueue" do
          @queues = []
          dqueues = Attr.get_dynamic_queues
          dqueues.each do |k, v|
            fetch = Fetch.new(:queues => ["@#{k}"], :strict => true)
            expanded = fetch.queues_cmd
            expanded.pop
            expanded = expanded.collect {|q| q.split(":").last }
            view_data = {
                'name' => k,
                'value' => Array(v).join(", "),
                'expanded' => expanded.join(", ")
            }
            @queues << view_data
          end
          
          @queues.sort! do |a, b|
            an = a['name']
            bn = b['name']
            if an == 'default'
              1
            elsif bn == 'default'
              -1
            else
              an <=> bn
            end
          end
          
          slim :dynamicqueue
        end

        app.post "/dynamicqueue" do
          dynamic_queues = Array(params['queues'])
          queues = {}
          dynamic_queues.each do |queue|
            key = queue['name']
            values = queue['value'].to_s.split(',').collect{|q| q.gsub(/\s/, '') }
            queues[key] = values
          end
          Attr.set_dynamic_queues(queues)
          redirect "#{root_path}dynamicqueue"
        end

        app.tabs["DynamicQueues"] = "dynamicqueue"
      end
    end
    
  end
end