# frozen_string_literal: true

# This concern can be added to a model for a support table to add the ability to lookup
# entries in these table using Rails.cache when calling find_by rather than hitting the
# database every time.
module SupportTableCache
  extend ActiveSupport::Concern

  included do
    class_attribute :support_table_cache_by_attributes, instance_accessor: false
    class_attribute :support_table_cache_ttl, instance_accessor: false

    class << self
      prepend FindByOverride unless include?(FindByOverride)
      private :support_table_cache_by_attributes=
    end

    after_commit :support_table_clear_cache_entries
  end

  class_methods do
    protected

    # Specify which attributes can be used for looking up records in the cache. Each value must
    # define a unique key, Multiple unique keys can be specified.
    # If multiple attributes are used to make up a unique key, then they should be passed in as an array.
    # @param attributes [String, Symbol, Array<String, Symbol>] Attributes that make up a unique key.
    # @param case_sensitive [Boolean] Indicate if strings should treated as case insensitive in the key.
    def cache_by(attributes, case_sensitive: true)
      attributes = Array(attributes).map(&:to_s).sort.freeze
      self.support_table_cache_by_attributes = (support_table_cache_by_attributes || []) + [[attributes, case_sensitive]]
    end
  end

  class << self
    # Disable the caching behavior. If a block is specified, then caching is only
    # disabled for that block. If no block is specified, then caching is disabled
    # globally.
    # @param disabled [Boolean] Caching will be disabled if this is true, enabled if false.
    def disable(disabled = true, &block)
      if block
        save_val = Thread.current[:support_table_cache_disabled]
        begin
          Thread.current[:support_table_cache_disabled] = !!disabled
        ensure
          Thread.current[:support_table_cache_disabled] = save_val
        end
      else
        @disabled = !!disabled
      end
    end

    def enable(&block)
      disable(false, &block)
    end

    # Return true if caching has been disabled.
    # @return [Boolean]
    def disabled?
      block_value = Thread.current[:support_table_cache_disabled]
      if block_value.nil?
        !!(defined?(@disabled) && @disabled)
      else
        block_value
      end
    end

    attr_writer :cache

    def cache
      if defined?(@cache)
        @cache
      elsif defined?(Rails.cache)
        Rails.cache
      end
    end

    # Generate a consistent cache key for a set of attributes. Returns nil if the attributes
    # are not cacheable.
    # @param klass [Class] The class to
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

  module FindByOverride
    # Override for the find_by method that looks in the cache first.
    def find_by(*args)
      return super if SupportTableCache.cache.nil? || SupportTableCache.disabled?

      cache_key = nil
      attributes = args.first if args.size == 1 && args.first.is_a?(Hash)
      if attributes
        support_table_cache_by_attributes.each do |attribute_names, case_sensitive|
          cache_key = SupportTableCache.cache_key(self, attributes, attribute_names, case_sensitive)
          break if cache_key
        end
      end

      if cache_key
        SupportTableCache.cache.fetch(cache_key, expires_in: support_table_cache_ttl) { super }
      else
        super
      end
    end
  end

  # Remove the cache entry for this record.
  # @return [void]
  def uncache
    cache_by_attributes = self.class.support_table_cache_by_attributes
    return if cache_by_attributes.blank? || SupportTableCache.cache.nil?

    cache_by_attributes.each do |attribute_names, case_sensitive|
      attributes = {}
      attribute_names.each do |name|
        attributes[name] = self[name]
      end
      cache_key = SupportTableCache.cache_key(self.class, attributes, attribute_names, case_sensitive)
      SupportTableCache.cache.delete(cache_key)
    end
  end

  private

  # Clear all combinations of the cacheable attributes whenever any attribute changes.
  # We have to make sure to clear the keys with the attribute values both before
  # and after the change.
  def support_table_clear_cache_entries
    cache_by_attributes = self.class.support_table_cache_by_attributes
    return if cache_by_attributes.blank? || SupportTableCache.cache.nil?

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
        SupportTableCache.cache.delete(cache_key)
      end
    end
  end
end
