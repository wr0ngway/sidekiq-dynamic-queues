require "spec_helper"

describe "Dynamic Queues" do

  include Sidekiq::DynamicQueues::Attributes
  Fetch = Sidekiq::DynamicQueues::Fetch

  def watch_queues(*queues)
    Sidekiq.redis do |r|
      queues.each {|q| r.sadd('queues', q) }
      r.del('queues') if queues.size == 0
    end
  end

  before(:each) do
    SomeJob.sidekiq_options('retry' => false, 'queue' => 'default')
    SomeJob.result = nil
    Sidekiq.redis {|r| r.flushall }
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

  context "#translate_from_cli" do

    it "passes through reqular queue name" do
      translated = Fetch.translate_from_cli("foo", "baz.bar", "bo_o", "bu-m")
      translated.should eq ["foo", "baz.bar", "bo_o", "bu-m"]
    end

    it "translates *" do
      translated = Fetch.translate_from_cli(".star.", ".star.foo",
                                            "foo.star.", "f.star.o")
      translated.should eq ["*", "*foo", "foo*", "f*o"]
    end

    it "translates !" do
      translated = Fetch.translate_from_cli(".not.", ".not.foo",
                                            "foo.not.", "f.not.o")
      translated.should eq ["!", "!foo", "foo!", "f!o"]
    end

    it "translates @" do
      translated = Fetch.translate_from_cli(".at.", ".at.foo",
                                            "foo.at.", "f.at.o")
      translated.should eq ["@", "@foo", "foo@", "f@o"]
    end

    it "translates multiple" do
      translated = Fetch.translate_from_cli(".not..star.", ".not..at.foo")
      translated.should eq ["!*", "!@foo"]
    end

  end

  context "basic queue patterns" do

    SFTO = Sidekiq::Fetcher::TIMEOUT

    before(:each) do
      watch_queues(*%w[high_x foo high_y superhigh_z])
    end

    it "uses default when wildcard empty" do
      watch_queues()
      fetch = Fetch.new(:queues => %w[*], :strict => true)
      fetch.queues_cmd.should eq ["queue:default", SFTO]
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

    it "can specify strict ordering with wildcards" do
      fetch = Fetch.new(:queues => %w[superhigh* high* *], :strict => true)
      fetch.queues_cmd.should eq ["queue:superhigh_z","queue:high_x",
                                  "queue:high_y", "queue:foo", SFTO]
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

    it "randomizes when not strict ordering" do
      fetch = Fetch.new(:queues => %w[*], :strict => false)

      3.times.any? { fetch.queues_cmd != fetch.queues_cmd }.should be_true

      %w[high_x foo high_y superhigh_z].all? do |q|
        fetch.queues_cmd.include?("queue:{q}")
      end
    end

  end

  context "redis backed queues" do

    it "can dynamically lookup queues" do
      set_dynamic_queue("mykey", ["foo", "bar"])
      fetch = Fetch.new(:queues => %w[@mykey], :strict => true)
      fetch.queues_cmd.should eq ["queue:foo", "queue:bar", SFTO]
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
      fetch.queues_cmd.should eq ["queue:foo", "queue:bar", SFTO]
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
      fetch.queues_cmd.should eq ["queue:foo", "queue:bar", SFTO]
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

  context "integration" do
    before(:all) do
      Sidekiq.options[:fetch] = Sidekiq::DynamicQueues::Fetch
      Sidekiq.options[:queue_refresh_timeout] = 0.01
    end

    it "does use the correct fetch strategy" do
      Sidekiq::Fetcher.strategy.should eq Sidekiq::DynamicQueues::Fetch
    end

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

    it "finds work on dynamic queue that doesn't exist till after sidekiq is waiting for jobs" do
      watch_queues(*%w[default])
      launcher = run_queues("*", :async => true)
      # give run_queues a chance to block on only the default queue given above
      sleep 0.1

      enqueue_on("other", SomeJob, 1)

      # sidekiq brpop's with a timeout of 1, so we need to wait longer than
      # that for it to re-evaluate the dynamic queues
      sleep 2
      timeout(5) do
        launcher.stop
      end
      SomeJob.result.should eq [1]
    end

  end

end
