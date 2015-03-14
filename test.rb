require 'bundler'
Bundler.setup
require 'pry'
require 'pry-stack_explorer'
require 'active_record'
require 'celluloid'
require 'logger'

logger                    = Logger.new("test.log")
logger.level              = Logger::DEBUG
$CELLULOID_TEST           = true
$CELLULOID_DEBUG          = true
Celluloid.logger          = logger
ActiveRecord::Base.logger = logger

$DISABLE_EXCEPTION_DETAIL = false
$POOLING                  = true
$EXPECTED_LINE            = "test.rb:49"

ActiveRecord::Base.establish_connection({
  adapter: "postgresql",
  host: "localhost",
  database: "postgres",
  pool: 5,
  encoding: "utf8",
  schema_search_path: "pg_catalog",
  timeout: 1000,
})

class Model < ActiveRecord::Base
  self.table_name = "pg_type"

  def self.undefined_constant
    NOT_A_CONSTANT
  end

  def self.undefined_local
    not_a_variable
  end
end

class Job
  include Celluloid

  task_class TaskThread

  def perform(breaker)
    print "thread: #{Thread.current.object_id}\n"
    ActiveRecord::Base.connection_pool.with_connection do
      Util.report
      Model.send breaker
    end
  end
end

module Util
  def self.report
    reserved_connections = ActiveRecord::Base.connection_pool.instance_variable_get(:@reserved_connections)

    details = {}
    reserved_connections.each_pair do |i,c|
      details[i] = c.object_id
    end
    print "reserved: #{details}\n"
  end

  def self.trigger_job(breaker)
    print "#{"-" * 160}\n"
    print "STARTING JOB\n"
    if $POOLING
      $pool.perform(breaker)
    else
      j = Job.new
      j.perform(breaker)
    end
  rescue Exception => e
    print "err: #{e.class}\n"
  ensure
    j.terminate if !$POOLING && j.alive?
    Util.report
  end
end

if $POOLING
  $pool = Job.pool(size: 10)
end
puts Model.inspect
Model.connection
puts Model.inspect

silence_warnings{ Model.first } # trigger schema load... warnings get raised because of column types used in the pg_type table

print "\n"
print "initial state:\n"
Util.report

print "\n"
print "non_leaker:\n"
5.times{ Util.trigger_job(:undefined_constant) }
Util.report

print "\n"
print "leaker:\n"
5.times{ Util.trigger_job(:undefined_local) }
Util.report

print "\n"
print "finished state:\n"
Util.report

reserved_connections = ActiveRecord::Base.connection_pool.instance_variable_get(:@reserved_connections)
dump = Celluloid.actor_system.stack_dump

suspects = {}
Thread.list.select do |thread|
  next unless reserved_connections.keys.include?(thread.object_id) && thread[:celluloid_actor]

  actor_state = dump.actors.find {|a| a.id == thread[:celluloid_actor].object_id}
  puts "Thread #{thread.object_id}: #{thread.inspect} holds a connection"
  puts actor_state.dump
  connection = reserved_connections.fetch(thread.object_id)

  suspects[thread.object_id] = {
    thread: thread,
    actor: thread.actor,
    state: actor_state,
    connection: connection,
  }
end

binding.pry

# Thread.list.select {|x| @reserved_connections.keys.include?(x.object_id)}.select(&:celluloid?).map(&:actor).map(&:behavior).map(&:subject)
