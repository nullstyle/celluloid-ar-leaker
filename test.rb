require 'bundler'
Bundler.setup
require 'active_record'
require 'celluloid'
require 'logger'

logger                    = Logger.new("test.log")
Celluloid.logger          = logger
ActiveRecord::Base.logger = logger

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
  def perform(breaker)
    ActiveRecord::Base.connection_pool.with_connection do
      Util.report
      Model.send breaker
    end
  end
end

module Util
  def self.report
    reserved_connections = ActiveRecord::Base.connection_pool.instance_variable_get(:@reserved_connections)
    puts "reserved: #{reserved_connections.keys.inspect}"
  end

  def self.trigger_job(breaker)
    $pool.perform(breaker)
  rescue => e
    puts "err: #{e.class}"
  end
end

$pool = Job.pool(size: 10)
silence_warnings{ Model.first } # trigger schema load... warnings get raised because of column types used in the pg_type table

puts
puts "initial state:"
Util.report

puts
puts "non_leaker:"
5.times{ Util.trigger_job(:undefined_constant) }
Util.report

puts
puts "leaker:"
5.times{ Util.trigger_job(:undefined_local) }
Util.report

puts
puts "finished state:"
Util.report
