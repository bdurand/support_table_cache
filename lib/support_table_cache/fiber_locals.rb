# frozen_string_literal: true

module SupportTableCache
  # Utility class for managing fiber-local variables. All values are stored in a single
  # hash inside the fiber's native local storage (Thread.current[], which is fiber-local
  # in Ruby) so the fiber-local namespace is not polluted with individual keys. Because
  # the state lives on the fiber itself, it is garbage collected along with the fiber
  # and cannot leak or be picked up by another fiber.
  class FiberLocals
    def initialize
      @locals_key = :"support_table_cache_locals_#{object_id}"
    end

    def [](key)
      locals = Thread.current[@locals_key]
      locals[key] if locals
    end

    def with(key, value)
      locals = Thread.current[@locals_key]
      if locals.nil?
        locals = {}
        Thread.current[@locals_key] = locals
      end

      exists = locals.key?(key)
      previous_value = locals[key]
      locals[key] = value

      begin
        yield
      ensure
        if exists
          locals[key] = previous_value
        else
          locals.delete(key)
          Thread.current[@locals_key] = nil if locals.empty?
        end
      end
    end
  end
end
