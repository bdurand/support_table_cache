# frozen_string_literal: true

module SupportTableCache
  # @api private

  module RelationOverride
    # Override for the find_by method that looks in the cache first.
    #
    # @param args [Array<Object>] Arguments passed to find_by.
    # @return [ActiveRecord::Base, nil] The found record or nil if not found.
    def find_by(*args)
      return super unless klass.include?(SupportTableCache)

      cache = klass.send(:current_support_table_cache)
      return super unless cache

      # Skip caching for has_many or has_many :through associations
      return super if is_a?(ActiveRecord::Associations::CollectionProxy)

      return super if select_values.present?

      # Only queries by simple attribute equality can be matched against cache keys.
      simple_attribute_query = args.empty? || (args.size == 1 && args.first.is_a?(Hash))
      return super unless simple_attribute_query

      return super unless support_table_cacheable_scope?

      # Queries inside a transaction could see uncommitted data that would be invalid
      # if the transaction is rolled back, so they cannot be cached.
      return super if SupportTableCache.open_transaction?(klass)

      attributes = (args.first || {}).stringify_keys

      # Apply any conditions from the current relation chain
      scope_conditions = where_values_hash.stringify_keys
      attributes = scope_conditions.merge(attributes) if scope_conditions.present?

      cache_key = SupportTableCache.cache_key_for_query(klass, attributes)

      if cache_key
        cache.fetch(cache_key, expires_in: support_table_cache_ttl) { super }
      else
        super
      end
    end

    # Override for the find_by! method that looks in the cache first.
    #
    # @param args [Array<Object>] Arguments passed to find_by!.
    # @return [ActiveRecord::Base] The found record.
    # @raise [ActiveRecord::RecordNotFound] if no record is found.
    def find_by!(*args)
      value = find_by(*args)
      unless value
        raise ActiveRecord::RecordNotFound.new("Couldn't find #{klass.name}", klass.name)
      end
      value
    end

    # Same as find_by, but performs a safety check to confirm the query will hit the cache.
    #
    # @param attributes [Hash] Attributes to find the record by.
    # @return [ActiveRecord::Base, nil] The found record or nil if not found.
    # @raise [ArgumentError] if the query cannot use the cache.
    def fetch_by(attributes)
      find_by_attribute_names = support_table_find_by_attribute_names(attributes)
      unless klass.support_table_cache_by_attributes.any? { |attribute_names, _ci| attribute_names == find_by_attribute_names }
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
        raise ActiveRecord::RecordNotFound.new("Couldn't find #{klass.name}", klass.name)
      end
      value
    end

    private

    # A relation can only be cached if all of its conditions are simple equality conditions
    # on the model's own attributes that can be represented in a cache key. Anything else
    # (SQL string conditions, ranges, OR clauses, joins, etc.) is not visible in
    # where_values_hash and could silently change which record the query returns.
    def support_table_cacheable_scope?
      return false unless where_clause.send(:predicates).size == where_values_hash.size
      return false if joins_values.present? || left_outer_joins_values.present?
      return false if group_values.present? || !having_clause.empty?
      return false if !from_clause.empty? || offset_value.present? || lock_value
      return false if eager_loading?

      true
    end

    def support_table_find_by_attribute_names(attributes)
      attributes ||= {}
      if scope_attributes.present?
        attributes = scope_attributes.merge(attributes)
      end
      attributes.keys.map(&:to_s).sort
    end
  end
end
