# frozen_string_literal: true

module SupportTableCache
  # Utility class for managing fiber-local variables. This implementation
  # does not pollute the global namespace.
  class FiberLocals
    def initialize
      @mutex = Mutex.new
      @locals = {}
    end

    def [](key)
      fiber_locals = nil
      @mutex.synchronize do
        fiber_locals = @locals[Fiber.current.object_id]
      end
      return nil if fiber_locals.nil?

      fiber_locals[key]
    end

    def with(key, value)
      fiber_id = Fiber.current.object_id
      fiber_locals = nil
      previous_value = nil
      inited_vars = false

      begin
        @mutex.synchronize do
          fiber_locals = @locals[fiber_id]
          if fiber_locals.nil?
            fiber_locals = {}
            @locals[fiber_id] = fiber_locals
            inited_vars = true
          end
        end

        previous_value = fiber_locals[key]
        fiber_locals[key] = value

        yield
      ensure
        if inited_vars
          @mutex.synchronize do
            @locals.delete(fiber_id)
          end
        else
          fiber_locals[key] = previous_value
        end
      end
    end
  end
end
