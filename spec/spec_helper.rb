# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" if File.exist?(ENV["BUNDLE_GEMFILE"])

require "active_record"

ActiveRecord::Base.establish_connection("adapter" => "sqlite3", "database" => ":memory:")

require_relative "../lib/support_table_cache"

ActiveRecord::Base.connection.tap do |connection|
  connection.create_table(:test_models) do |t|
    t.string :name, index: {unique: true}
    t.string :code
    t.string :group
    t.integer :value
    t.index [:group, :code], unique: true
  end

  connection.create_table(:parent_models) do |t|
    t.string :name, index: {unique: true}
    t.integer :test_model_id
  end

  connection.create_table(:default_scope_models) do |t|
    t.string :name, index: {unique: true}
    t.string :label
    t.datetime :deleted_at, null: true
  end

  connection.create_table(:things) do |t|
    t.string :name
  end

  connection.create_table(:other_things) do |t|
    t.integer :thing_id, index: true
    t.integer :test_model_id, index: true
  end
end

class TestModel < ActiveRecord::Base
  include SupportTableCache

  cache_by :name
  cache_by [:group, :code], case_sensitive: false

  self.support_table_cache_ttl = 60
end

class ParentModel < ActiveRecord::Base
  include SupportTableCache::Associations

  belongs_to :test_model
  cache_belongs_to :test_model
end

class Subclass < TestModel
  cache_by false
  cache_by :code, case_sensitive: false
  cache_by :code, case_sensitive: true
end

class DefaultScopeModel < ActiveRecord::Base
  include SupportTableCache

  cache_by :name, where: {deleted_at: nil}

  default_scope { where(deleted_at: nil) }
end

class Thing < ActiveRecord::Base
  has_many :other_things
  has_many :test_models, through: :other_things
end

class OtherThing < ActiveRecord::Base
  belongs_to :test_model
  belongs_to :thing
end

SupportTableCache.cache = ActiveSupport::Cache::MemoryStore.new

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.default_formatter = "doc" if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed

  config.before do
    TestModel.delete_all
    ParentModel.delete_all
    DefaultScopeModel.unscoped.delete_all
    SupportTableCache.cache.clear
  end
end
