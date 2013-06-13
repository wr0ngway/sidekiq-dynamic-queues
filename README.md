A sidekiq plugin for specifying the queues a worker pulls from with wildcards, negations, or dynamic look up from redis.

Authored against Sidekiq 2.9.0, so it at least works with that - try running the tests if you use a different version of sidekiq

[![Build Status](https://secure.travis-ci.org/wr0ngway/sidekiq-dynamic-queues.png)](http://travis-ci.org/wr0ngway/sidekiq-dynamic-queues)

Usage:

If creating a gem of your own that uses sidekiq-dynamic-queues, you may have to add an explicit require statement at the top of your Rakefile:

    require 'sidekiq-dynamic-queues'

Configure by:
 
    Sidekiq.configure_server do |config|
        config.options[:fetch] = Sidekiq::DynamicQueues::Fetch
    end
    
Start your workers with a queue that can contain '\*' (.star.) for zero-or more of any character, '!' (.not.) to exclude the following pattern, or @key (.at.key) to look up the patterns from redis.  The version in parens is required to get around the sidekiq cli's restriction on queue names.  Some examples help:

    sidekiq -q foo

Pulls jobs from the queue 'foo'

    sidekiq -q .star.

Pulls jobs from any queue

    sidekiq -q .star.foo

Pulls jobs from queues that end in foo

    sidekiq -q .star.foo.star.

Pulls jobs from queues whose names contain foo

    sidekiq -q .star.foo.star. -q .not.foobar

Pulls jobs from queues whose names contain foo except the foobar queue

    sidekiq -q .star.foo.star. -q .not..star.bar

Pulls jobs from queues whose names contain foo except queues whose names end in bar

    sidekiq -q .at.key

Pulls jobs from queue names stored in redis (use Sidekiq::DynamicQueues::Attributes.set\_dynamic\_queue("key", ["queuename1", "queuename2"]) to set them)

    sidekiq -q .star. -q .not..at.key

Pulls jobs from any queue except ones stored in redis

    sidekiq -q .at.

Pulls jobs from queue names stored in redis using the hostname of the worker

    Sidekiq::DynamicQueues::Attributes.set_dynamic_queue("key", ["*foo*", "!*bar"])
    sidekiq -q .at.key 

Pulls jobs from queue names stored in redis, with wildcards/negations


There is also a tab in the sidekiq-web UI that allows you to define the dynamic queues  To activate it, you need to require 'sidekiq-dynamic-queues-server' in whatever initializer you use to bring up sidekiq-web.


Contributors:

Matt Conway ( https://github.com/wr0ngway )