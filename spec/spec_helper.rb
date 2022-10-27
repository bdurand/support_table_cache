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

class DefaultScopeModel < ActiveRecord::Base
  unless table_exists?
    connection.create_table(table_name) do |t|
      t.string :name, index: {unique: true}
      t.string :label
      t.datetime :deleted_at, null: true
    end
  end

  include SupportTableCache

  cache_by :name, where: {deleted_at: nil}

  default_scope { where(deleted_at: nil) }
end

SupportTableCache.cache = ActiveSupport::Cache::MemoryStore.new

RSpec.configure do |config|
  config.order = :random

  config.before do
    TestModel.delete_all
    ParentModel.delete_all
    DefaultScopeModel.unscoped.delete_all
    SupportTableCache.cache.clear
  end
end
