ENV['RACK_ENV'] = 'test'

require 'spec_helper'
require 'rack'
require 'rack/test'
require 'sidekiq-dynamic-queues-server'

Sinatra::Base.set :environment, :test

describe "Dynamic Queues pages" do
  include Rack::Test::Methods
  include Sidekiq::DynamicQueues::Attributes
  
  def app
    @app ||= Sidekiq::Web.new
  end

  before(:each) do
    Sidekiq.redis {|r| r.flushall }
  end

  context "existence in application" do

    it "should respond to it's url" do
      get "/dynamicqueue"
      last_response.should be_ok
    end

    it "should display its tab" do
      get "/"
      last_response.body.should include '<a href="/dynamicqueue">DynamicQueues</a>'
    end

  end

  context "show dynamic queues table" do

    it "should shows default queue when nothing set" do
      get "/dynamicqueue"

      last_response.body.should include 'default'
    end

    it "should shows names of queues" do
      set_dynamic_queue("key_one", ["foo"])
      set_dynamic_queue("key_two", ["bar"])

      get "/dynamicqueue"

      last_response.body.should include 'key_one'
      last_response.body.should include 'key_two'
    end

    it "should shows values of queues" do
      set_dynamic_queue("key_one", ["foo"])
      set_dynamic_queue("key_two", ["bar", "baz"])

      get "/dynamicqueue"

      last_response.body.should include 'foo'
      last_response.body.should include 'bar, baz'
    end

  end

  context "remove queue link" do

    it "should show remove link for queue" do
      set_dynamic_queue("key_one", ["foo"])

      get "/dynamicqueue"

      last_response.body.should match /<a .*href=['"]#remove['"].*>/
    end

    it "should show add link" do
      get "/dynamicqueue"

      last_response.body.should match /<a .*href=['"]#add['"].*>/
    end

  end

  context "form to edit queues" do

    it "should have form to edit queues" do
      get "/dynamicqueue"

      last_response.body.should match /<form action="\/dynamicqueue"/
    end
    
    it "should show input fields" do
      set_dynamic_queue("key_one", ["foo"])
      set_dynamic_queue("key_two", ["bar", "baz"])
      get "/dynamicqueue"

      last_response.body.should include '<input type="text" id="input-0-name" name="queues[][name]" value="key_one" />'
      last_response.body.should include '<input type="text" id="input-0-value" name="queues[][value]" value="foo" />'
      last_response.body.should include '<input type="text" id="input-1-name" name="queues[][name]" value="key_two" />'
      last_response.body.should include '<input type="text" id="input-1-value" name="queues[][value]" value="bar, baz" />'
    end

    it "should delete queues on empty queue submit" do
      set_dynamic_queue("key_two", ["bar", "baz"])
      post "/dynamicqueue", {'queues' => [{'name' => "key_two", "value" => ""}]}

      last_response.should be_redirect
      last_response['Location'].should match /dynamicqueue/
      get_dynamic_queue("key_two", []).should be_empty
    end

    it "should create queues" do
      post "/dynamicqueue", {'queues' => [{'name' => "key_two", "value" => " foo, bar ,baz "}]}

      last_response.should be_redirect
      last_response['Location'].should match /dynamicqueue/
      get_dynamic_queue("key_two").should == %w{foo bar baz}
    end

    it "should update queues" do
      set_dynamic_queue("key_two", ["bar", "baz"])
      post "/dynamicqueue", {'queues' => [{'name' => "key_two", "value" => "foo,bar,baz"}]}

      last_response.should be_redirect
      last_response['Location'].should match /dynamicqueue/
      get_dynamic_queue("key_two").should == %w{foo bar baz}
    end

  end

end
