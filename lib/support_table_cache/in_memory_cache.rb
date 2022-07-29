# frozen_string_literal: true

module SupportTableCache
  # An optimized cache implementation that can be used when all records can easily fit
  # in memory and they are never changed. It is intended for use with small, static support
  # tables only.
  #
  # This cache will not cache nil values. This is to prevent the cache from filling up with
  # cache misses since there is no purging mechanism.
  class InMemoryCache
    def initialize
      @cache = {}
      @mutex = Mutex.new
    end

    def fetch(key, expires_in: nil)
      serialized_value, expire_at = @cache[key]
      if serialized_value.nil? || (expire_at && expire_at < Process.clock_gettime(Process::CLOCK_MONOTONIC))
        value = yield
        return nil if value.nil?

        if expires_in
          expire_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + expires_in
        end

        serialized_value = Marshal.dump(yield)

        @mutex.synchronize do
          @cache[key] = [serialized_value, expire_at]
        end
      end
      Marshal.load(serialized_value)
    end

    def delete(key)
      @cache.delete(key)
    end

    def clear
      @cache.clear
    end
  end
end
