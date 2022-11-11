# frozen_string_literal: true

require_relative "support_table_cache/associations"
require_relative "support_table_cache/find_by_override"
require_relative "support_table_cache/relation_override"
require_relative "support_table_cache/memory_cache"

# This concern can be added to a model to add the ability to look up entries in the table
# using Rails.cache when calling find_by rather than hitting the database every time.
module SupportTableCache
  extend ActiveSupport::Concern

  included do
    # @api private Used to store the list of attribute names used for caching.
    class_attribute :support_table_cache_by_attributes, instance_accessor: false

    # Set the time to live in seconds for records in the cache.
    class_attribute :support_table_cache_ttl, instance_accessor: false

    # @api private
    class_attribute :support_table_cache_impl, instance_accessor: false

    unless ActiveRecord::Relation.include?(RelationOverride)
      ActiveRecord::Relation.prepend(RelationOverride)
    end

    class << self
      prepend FindByOverride unless include?(FindByOverride)
      private :support_table_cache_by_attributes=
      private :support_table_cache_impl
      private :support_table_cache_impl=
    end

    after_commit :support_table_clear_cache_entries
  end

  module ClassMethods
    # Disable the caching behavior for this class within the block. The disabled setting
    # for a class will always take precedence over the global setting.
    #
    # @param disabled [Boolean] Caching will be disabled if this is true and enabled if false.
    # @yieldreturn The return value of the block.
    def disable_cache(disabled = true, &block)
      varname = "support_table_cache_disabled:#{name}"
      save_val = Thread.current.thread_variable_get(varname)
      begin
        Thread.current.thread_variable_set(varname, !!disabled)
        yield
      ensure
        Thread.current.thread_variable_set(varname, save_val)
      end
    end

    # Enable the caching behavior for this class within the block. The enabled setting
    # for a class will always take precedence over the global setting.
    #
    # @return [void]
    def enable_cache
      disable_cache(false, &block)
    end

    # Load all records into the cache. You should only call this method on small tables with
    # a few dozen rows at most because it will load each row one at a time.
    #
    # @return [void]
    def load_cache
      cache = current_support_table_cache
      return super if cache.nil?

      find_each do |record|
        support_table_cache_by_attributes.each do |attribute_names, case_sensitive|
          attributes = record.attributes.select { |name, value| attribute_names.include?(name) }
          cache_key = SupportTableCache.cache_key(self, attributes, attribute_names, case_sensitive)
          cache.fetch(cache_key, expires_in: support_table_cache_ttl) { record }
        end
      end
    end

    # Set a class-specific cache to use in lieu of the global cache.
    #
    # @param cache [ActiveSupport::Cache::Store, Symbol] The cache instance to use. You can also
    #   specify the value :memory to use an optimized in-memory cache.
    # @return [void]
    def support_table_cache=(cache)
      cache = MemoryCache.new if cache == :memory
      self.support_table_cache_impl = cache
    end

    protected

    # Specify which attributes can be used for looking up records in the cache. Each value must
    # define a unique key, Multiple unique keys can be specified.
    #
    # If multiple attributes are used to make up a unique key, then they should be passed in as an array.
    #
    # If you need to remove caching setup in a superclass, you can pass in the value false to reset
    # cache behavior on the class.
    #
    # @param attributes [String, Symbol, Array<String, Symbol>, FalseClass] Attributes that make up a unique key.
    # @param case_sensitive [Boolean] Indicate if strings should treated as case insensitive in the key.
    # @param where [Hash] A hash representing a hard coded set of attributes that must match a query in order
    #   to cache the result. If a model has a default scope, then this value should be set to match the
    #   where clause in that scope.
    # @return [void]
    def cache_by(attributes, case_sensitive: true, where: nil)
      if attributes == false
        self.support_table_cache_by_attributes = []
        return
      end

      attributes = Array(attributes).map(&:to_s).sort.freeze

      if where
        unless where.is_a?(Hash)
          raise ArgumentError.new("where must be a Hash")
        end
        where = where.stringify_keys
      end

      self.support_table_cache_by_attributes ||= []
      support_table_cache_by_attributes.delete_if { |data| data.first == attributes }
      self.support_table_cache_by_attributes += [[attributes, case_sensitive, where]]
    end

    private

    def support_table_cache_disabled?
      current_block_value = Thread.current.thread_variable_get("support_table_cache_disabled:#{name}")
      if current_block_value.nil?
        SupportTableCache.disabled?
      else
        current_block_value
      end
    end

    def current_support_table_cache
      return nil? if support_table_cache_disabled?
      SupportTableCache.testing_cache || support_table_cache_impl || SupportTableCache.cache
    end
  end

  class << self
    # Disable the caching behavior for all classes. If a block is specified, then caching is only
    # disabled for that block. If no block is specified, then caching is disabled globally.
    #
    # @param disabled [Boolean] Caching will be disabled if this is true and enabled if false.
    # @yieldreturn The return value of the block.
    def disable(disabled = true, &block)
      if block
        save_val = Thread.current.thread_variable_get(:support_table_cache_disabled)
        begin
          Thread.current.thread_variable_set(:support_table_cache_disabled, !!disabled)
        ensure
          Thread.current.thread_variable_set(:support_table_cache_disabled, save_val)
        end
      else
        @disabled = !!disabled
      end
    end

    # Enable the caching behavior for all classes. If a block is specified, then caching is only
    # enabled for that block. If no block is specified, then caching is enabled globally.
    #
    # @yieldreturn The return value of the block.
    def enable(&block)
      disable(false, &block)
    end

    # Return true if caching has been disabled.
    # @return [Boolean]
    def disabled?
      block_value = Thread.current.thread_variable_get(:support_table_cache_disabled)
      if block_value.nil?
        !!(defined?(@disabled) && @disabled)
      else
        block_value
      end
    end

    # Set the global cache to use.
    # @param value [ActiveSupport::Cache::Store, Symbol] The cache instance to use. You can also
    #   specify the value :memory to use an optimized in-memory cache.
    # @return [void]
    def cache=(value)
      value = MemoryCache.new if value == :memory
      @cache = value
    end

    # Get the global cache (will default to `Rails.cache` if running in a Rails environment).
    #
    # @return [ActiveSupport::Cache::Store]
    def cache
      if testing_cache
        testing_cache
      elsif defined?(@cache)
        @cache
      elsif defined?(Rails.cache)
        Rails.cache
      end
    end

    # Enter test mode for a block. New caches will be used within each test mode block. You
    # can use this to wrap your test methods so that cached values from one test don't show up
    # in subsequent tests.
    #
    # @return [void]
    def testing!(&block)
      save_val = Thread.current.thread_variable_get(:support_table_cache_test_cache)
      if save_val.nil?
        Thread.current.thread_variable_set(:support_table_cache_test_cache, MemoryCache.new)
      end
      begin
        yield
      ensure
        Thread.current.thread_variable_set(:support_table_cache_test_cache, save_val)
      end
    end

    # Get the current test mode cache. This will only return a value inside of a `testing!` block.
    #
    # @return [SupportTableCache::MemoryCache]
    # @api private
    def testing_cache
      unless defined?(@cache) && @cache.nil?
        Thread.current.thread_variable_get(:support_table_cache_test_cache)
      end
    end

    # Generate a consistent cache key for a set of attributes. It will return nil if the attributes
    # are not cacheable.
    #
    # @param klass [Class] The class that is being cached.
    # @param attributes [Hash] The attributes used to find a record.
    # @param key_attribute_names [Array] List of attributes that can be used as a key in the cache.
    # @param case_sensitive [Boolean] Indicator if string values are case-sensitive in the cache key.
    # @return [String]
    # @api private
    def cache_key(klass, attributes, key_attribute_names, case_sensitive)
      return nil if attributes.blank? || key_attribute_names.blank?

      sorted_names = attributes.keys.map(&:to_s).sort
      return nil unless sorted_names == key_attribute_names

      sorted_attributes = {}
      sorted_names.each do |attribute_name|
        value = (attributes[attribute_name] || attributes[attribute_name.to_sym])
        if !case_sensitive && (value.is_a?(String) || value.is_a?(Symbol))
          value = value.to_s.downcase
        end
        sorted_attributes[attribute_name] = value
      end

      [klass.name, sorted_attributes]
    end
  end

  # Remove the cache entry for this record.
  #
  # @return [void]
  def uncache
    cache_by_attributes = self.class.support_table_cache_by_attributes
    return if cache_by_attributes.blank?

    cache = self.class.send(:current_support_table_cache)
    return if cache.nil?

    cache_by_attributes.each do |attribute_names, case_sensitive|
      attributes = {}
      attribute_names.each do |name|
        attributes[name] = self[name]
      end
      cache_key = SupportTableCache.cache_key(self.class, attributes, attribute_names, case_sensitive)
      cache.delete(cache_key)
    end
  end

  private

  # Clear all combinations of the cacheable attributes whenever any attribute changes.
  # We have to make sure to clear the keys with the attribute values both before
  # and after the change.
  def support_table_clear_cache_entries
    cache_by_attributes = self.class.support_table_cache_by_attributes
    return if cache_by_attributes.blank?

    cache = self.class.send(:current_support_table_cache)
    return if cache.nil?

    cache_by_attributes.each do |attribute_names, case_sensitive|
      attributes_before = {} if saved_change_to_id.blank? || saved_change_to_id.first.present?
      attributes_after = {} if saved_change_to_id.blank? || saved_change_to_id.last.present?
      attribute_names.each do |name|
        if attributes_before
          attributes_before[name] = (saved_changes.include?(name) ? saved_changes[name].first : self[name])
        end
        if attributes_after
          attributes_after[name] = self[name]
        end
      end
      [attributes_before, attributes_after].compact.uniq.each do |attributes|
        cache_key = SupportTableCache.cache_key(self.class, attributes, attribute_names, case_sensitive)
        cache.delete(cache_key)
      end
    end
  end
end
