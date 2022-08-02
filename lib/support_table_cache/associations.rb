# frozen_string_literal: true

module SupportTableCache
  # Extension to non-support table models for caching belongs_to associations to support tables.
  module Associations
    extend ActiveSupport::Concern

    module ClassMethods
      # Specify that a belongs_to association should use the cache. This will override the reader method
      # for the association so that it queries from the cache. The association must already be defined.
      #
      # @param association_name [Symbol, String] The association name to cache.
      # @return [void]
      def cache_belongs_to(association_name)
        reflection = reflections[association_name.to_s]

        unless reflection&.belongs_to?
          raise ArguementError.new("The belongs_to #{association_name} association is not defined")
        end

        if reflection.scopes.present?
          raise ArguementError.new("Cannot cache belongs_to #{association_name} association because it has a scope")
        end

        class_eval <<~RUBY, __FILE__, __LINE__ + 1
          def #{association_name}_with_cache
            foreign_key = self.send(#{reflection.foreign_key.inspect})
            return nil if foreign_key.nil?
            key = [#{reflection.class_name.inspect}, {#{reflection.association_primary_key.inspect} => foreign_key}]
            cache = #{reflection.class_name}.send(:current_support_table_cache)
            ttl = #{reflection.class_name}.send(:support_table_cache_ttl)
            if cache
              cache.fetch(key, expires_in: ttl) do
                #{association_name}_without_cache
              end
            else
              #{association_name}_without_cache
            end
          end

          alias_method :#{association_name}_without_cache, :#{association_name}
          alias_method :#{association_name}, :#{association_name}_with_cache
        RUBY
      end
    end
  end
end
