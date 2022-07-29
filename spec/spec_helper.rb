# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" if File.exist?(ENV["BUNDLE_GEMFILE"])

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

  cache_by :id
  cache_by :name
  cache_by [:group, :code], case_sensitive: false

  self.support_table_cache_ttl = 60
end

class ParentModel < ActiveRecord::Base
  unless table_exists?
    connection.create_table(table_name) do |t|
      t.string :name, index: {unique: true}
      t.integer :test_model_id
    end
  end

  include SupportTableCache::Associations

  belongs_to :test_model
  cache_belongs_to :test_model
end

SupportTableCache.cache = ActiveSupport::Cache::MemoryStore.new

RSpec.configure do |config|
  config.order = :random

  config.before do
    TestModel.delete_all
    SupportTableCache.cache.clear
  end
end
