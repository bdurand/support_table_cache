# frozen_string_literal: true

module SupportTableCache
  # @api private

  module RelationOverride
    # Override for the find_by method that looks in the cache first.
    def find_by(*args)
      return super unless klass.include?(SupportTableCache)

      cache = klass.send(:current_support_table_cache)
      return super unless cache

      cache_key = nil
      attributes = ((args.size == 1 && args.first.is_a?(Hash)) ? args.first.stringify_keys : {})

      # Apply any attributes from the current relation chain
      if scope_attributes.present?
        attributes = scope_attributes.stringify_keys.merge(attributes)
      end

      if attributes.present?
        support_table_cache_by_attributes.each do |attribute_names, case_sensitive, where|
          where&.each do |name, value|
            if attributes.include?(name) && attributes[name] == value
              attributes.delete(name)
            else
              return super
            end
          end
          cache_key = SupportTableCache.cache_key(klass, attributes, attribute_names, case_sensitive)
          break if cache_key
        end
      end

      if cache_key
        cache.fetch(cache_key, expires_in: support_table_cache_ttl) { super }
      else
        super
      end
    end

    # Override for the find_by! method that looks in the cache first.
    # @raise ActiveRecord::RecordNotFound if no record is found.
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
    # @raise ArgumentError if the query cannot use the cache.
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
    # @raise ArgumentError if the query cannot use the cache.
    # @raise ActiveRecord::RecordNotFound if no record is found.
    def fetch_by!(attributes)
      value = fetch_by(attributes)
      if value.nil?
        raise ActiveRecord::RecordNotFound.new("Couldn't find #{klass.name}", klass.name)
      end
      value
    end

    private

    def support_table_find_by_attribute_names(attributes)
      attributes ||= {}
      if scope_attributes.present?
        attributes = scope_attributes.merge(attributes)
      end
      attributes.keys.map(&:to_s).sort
    end
  end
end
