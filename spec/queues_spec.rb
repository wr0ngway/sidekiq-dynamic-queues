require "spec_helper"

describe "Dynamic Queues" do

  include Sidekiq::DynamicQueues::Attributes
  
  def watch_queues(*queues)
    Sidekiq.redis do |r|
      queues.each {|q| r.sadd('queues', q) }
    end    
  end
  
  before(:each) do
    SomeJob.sidekiq_options('retry' => false, 'queue' => 'default')
    SomeJob.result = nil
    Sidekiq.redis {|r| r.flushall }
  end

  context "basic behavior still works" do

    it "can work on different queues" do
      SomeJob.perform_async(1)
      run_queues("default")
      SomeJob.result.should eq [1] 
      enqueue_on("other", SomeJob, 2)
      run_queues("other")
      SomeJob.result.should eq [2] 
    end

    it "can work on multiple queues" do
      SomeJob.perform_async(1)
      run_queues("other", "default")
      SomeJob.result.should eq [1] 
      enqueue_on("other", SomeJob, 2)
      run_queues("default", "other")
      SomeJob.result.should eq [2] 
    end

  end

  context "attributes" do

    it "should always have a fallback pattern" do
      get_dynamic_queues.should == {'default' => ['*']}
    end
    
    it "should allow setting single patterns" do
      get_dynamic_queue('foo').should == ['*']
      set_dynamic_queue('foo', ['bar'])
      get_dynamic_queue('foo').should == ['bar']
    end
    
    it "should allow setting multiple patterns" do
      set_dynamic_queues({'foo' => ['bar'], 'baz' => ['boo']})
      get_dynamic_queues.should == {'foo' => ['bar'], 'baz' => ['boo'], 'default' => ['*']}
    end
    
    it "should remove mapping when setting empty value" do
      get_dynamic_queues
      set_dynamic_queues({'foo' => ['bar'], 'baz' => ['boo']})
      get_dynamic_queues.should == {'foo' => ['bar'], 'baz' => ['boo'], 'default' => ['*']}
      
      set_dynamic_queues({'foo' => [], 'baz' => ['boo']})
      get_dynamic_queues.should == {'baz' => ['boo'], 'default' => ['*']}
      set_dynamic_queues({'baz' => nil})
      get_dynamic_queues.should == {'default' => ['*']}
      
      set_dynamic_queues({'foo' => ['bar'], 'baz' => ['boo']})
      set_dynamic_queue('foo', [])
      get_dynamic_queues.should == {'baz' => ['boo'], 'default' => ['*']}
      set_dynamic_queue('baz', nil)
      get_dynamic_queues.should == {'default' => ['*']}
    end
    
    
  end
  
  context "basic queue patterns" do

    Fetch = Sidekiq::DynamicQueues::Fetch
    SFTO = Sidekiq::Fetcher::TIMEOUT
    
    before(:each) do
      watch_queues(*%w[high_x foo high_y superhigh_z])
    end

    it "can specify simple queues" do
      fetch = Fetch.new(:queues => %w[foo], :strict => true)
      fetch.queues_cmd.should eq ["queue:foo", SFTO]

      fetch = Fetch.new(:queues => %w[foo bar], :strict => true)
      fetch.queues_cmd.should eq ["queue:foo", "queue:bar", SFTO]
    end

    it "can specify simple wildcard" do
      fetch = Fetch.new(:queues => %w[*], :strict => true)
      fetch.queues_cmd.should eq ["queue:foo", "queue:high_x",
                                  "queue:high_y", "queue:superhigh_z", SFTO]
    end

    it "can include queues with pattern"do
      fetch = Fetch.new(:queues => %w[high*], :strict => true)
      fetch.queues_cmd.should eq ["queue:high_x", "queue:high_y", SFTO]
      
      fetch = Fetch.new(:queues => %w[*high_z], :strict => true)
      fetch.queues_cmd.should eq ["queue:superhigh_z", SFTO]

      fetch = Fetch.new(:queues => %w[*high*], :strict => true)
      fetch.queues_cmd.should eq ["queue:high_x", "queue:high_y",
                                  "queue:superhigh_z", SFTO]
    end

    it "can blacklist queues" do
      fetch = Fetch.new(:queues => %w[* !foo], :strict => true)
      fetch.queues_cmd.should eq ["queue:high_x", "queue:high_y",
                                  "queue:superhigh_z", SFTO]
    end

    it "can blacklist queues with pattern" do
      fetch = Fetch.new(:queues => %w[* !*high*], :strict => true)
      fetch.queues_cmd.should eq ["queue:foo", SFTO]
    end

  end

  context "redis backed queues" do

    it "can dynamically lookup queues" do
      set_dynamic_queue("mykey", ["foo", "bar"])
      fetch = Fetch.new(:queues => %w[@mykey], :strict => true)
      fetch.queues_cmd.should eq ["queue:bar", "queue:foo", SFTO]
    end

    it "can blacklist dynamic queues" do
      watch_queues(*%w[high_x foo high_y superhigh_z])

      set_dynamic_queue("mykey", ["foo"])
      fetch = Fetch.new(:queues => %w[* !@mykey], :strict => true)
      fetch.queues_cmd.should eq ["queue:high_x", "queue:high_y",
                                  "queue:superhigh_z", SFTO]
    end

    it "can blacklist dynamic queues with negation" do
      watch_queues(*%w[high_x foo high_y superhigh_z])

      set_dynamic_queue("mykey", ["!foo", "high_x"])
      fetch = Fetch.new(:queues => %w[!@mykey], :strict => true)
      fetch.queues_cmd.should eq ["queue:foo", SFTO]
    end

    it "uses hostname as default key in dynamic queues" do
      host = `hostname`.chomp
      set_dynamic_queue(host, ["foo", "bar"])
      fetch = Fetch.new(:queues => %w[@], :strict => true)
      fetch.queues_cmd.should eq ["queue:bar", "queue:foo", SFTO]
    end

    it "can use wildcards in dynamic queues" do
      watch_queues(*%w[high_x foo high_y superhigh_z])

      set_dynamic_queue("mykey", ["*high*", "!high_y"])
      fetch = Fetch.new(:queues => %w[@mykey], :strict => true)
      fetch.queues_cmd.should eq ["queue:high_x", "queue:superhigh_z", SFTO]
    end

    it "falls back to default queues when missing" do
      set_dynamic_queue("default", ["foo", "bar"])
      fetch = Fetch.new(:queues => %w[@mykey], :strict => true)
      fetch.queues_cmd.should eq ["queue:bar", "queue:foo", SFTO]
    end

    it "falls back to all queues when missing and no default" do
      watch_queues(*%w[high_x foo])
      fetch = Fetch.new(:queues => %w[@mykey], :strict => true)
      fetch.queues_cmd.should eq ["queue:foo", "queue:high_x", SFTO]
    end

    it "falls back to all queues when missing and no default and keep up to date" do
      watch_queues(*%w[high_x foo])
      fetch = Fetch.new(:queues => %w[@mykey], :strict => true)
      fetch.queues_cmd.should eq ["queue:foo", "queue:high_x", SFTO]
      watch_queues(*%w[bar])
      fetch.queues_cmd.should eq ["queue:bar", "queue:foo", "queue:high_x", SFTO]
    end

  end

end
