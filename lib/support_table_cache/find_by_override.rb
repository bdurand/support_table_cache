# frozen_string_literal: true

module SupportTableCache
  # @api private
  module FindByOverride
    # Override for the find_by method that looks in the cache first.
    def find_by(*args)
      cache = current_support_table_cache
      return super unless cache

      # Only queries by simple attribute equality can be matched against cache keys.
      return super unless args.size == 1 && args.first.is_a?(Hash)

      # If the class has any scope applied (a default scope or a scoping block), defer to
      # the relation override, which checks whether the scoped query can be cached.
      return super if all.values.present?

      # Queries inside a transaction could see uncommitted data that would be invalid
      # if the transaction is rolled back, so they cannot be cached.
      return super if SupportTableCache.open_transaction?(self)

      cache_key = SupportTableCache.cache_key_for_query(self, args.first.stringify_keys)

      if cache_key
        cache.fetch(cache_key, expires_in: support_table_cache_ttl) { super }
      else
        super
      end
    end

    # Same as find_by, but performs a safety check to confirm the query will hit the cache.
    #
    # @param attributes [Hash] Attributes to find the record by.
    # @return [ActiveRecord::Base, nil] The found record or nil if not found.
    # @raise [ArgumentError] if the query cannot use the cache.
    def fetch_by(attributes)
      find_by_attribute_names = support_table_find_by_attribute_names(attributes)
      unless support_table_cache_by_attributes.any? { |attribute_names, _ci, _where| attribute_names == find_by_attribute_names }
        raise ArgumentError.new("#{name} does not cache queries by #{find_by_attribute_names.to_sentence}")
      end
      find_by(attributes)
    end

    # Same as find_by!, but performs a safety check to confirm the query will hit the cache.
    #
    # @param attributes [Hash] Attributes to find the record by.
    # @return [ActiveRecord::Base] The found record.
    # @raise [ArgumentError] if the query cannot use the cache.
    # @raise [ActiveRecord::RecordNotFound] if no record is found.
    def fetch_by!(attributes)
      value = fetch_by(attributes)
      if value.nil?
        raise ActiveRecord::RecordNotFound.new("Couldn't find #{name}", name)
      end
      value
    end

    private

    def support_table_find_by_attribute_names(attributes)
      attributes ||= {}
      if respond_to?(:scope_attributes) && scope_attributes.present?
        attributes = scope_attributes.merge(attributes)
      end
      attributes.keys.map(&:to_s).sort
    end
  end
end
