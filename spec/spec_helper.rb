require "bundler/setup"

require "active_record"

ActiveRecord::Base.establish_connection("adapter" => "sqlite3", "database" => ":memory:")

require_relative "../lib/support_table_cache"

class TestModel < ActiveRecord::Base
  unless table_exists?
    connection.create_table(table_name) do |t|
      t.string :name, index: {unique: true}
      t.string :code
      t.string :group
      t.integer :value
      t.index [:group, :code], unique: true
    end
  end

  include SupportTableCache

  cache_by :name
  cache_by [:group, :code], case_sensitive: false

  self.support_table_cache_ttl = 60
end

SupportTableCache.cache = ActiveSupport::Cache::MemoryStore.new

RSpec.configure do |config|
  config.before do
    TestModel.delete_all
    SupportTableCache.cache.clear
  end
end
