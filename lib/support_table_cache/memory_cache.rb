# frozen_string_literal: true

module SupportTableCache
  # An optimized cache implementation that can be used when all records can easily fit
  # in memory and are never changed. It is intended for use with small, static support
  # tables only.
  #
  # This cache will not store nil values. This is to prevent the cache from filling up with
  # cache misses because there is no purging mechanism.
  class MemoryCache
    # Create a new memory cache.
    #
    # @return [SupportTableCache::MemoryCache]
    def initialize
      @cache = {}
      @mutex = Mutex.new
    end

    # Fetch a value from the cache. If the key is not found or has expired, yields to get a new value.
    #
    # @param key [Object] The cache key.
    # @param expires_in [Integer, nil] Time in seconds until the cached value expires.
    # @yield Block to execute to get a new value if the key is not cached.
    # @return [Object, nil] The cached value or the result of the block, or nil if no value is found.
    def fetch(key, expires_in: nil)
      serialized_value, expire_at = @cache[key]
      if serialized_value.nil? || (expire_at && expire_at < Process.clock_gettime(Process::CLOCK_MONOTONIC))
        value = yield if block_given?
        return nil if value.nil?
        write(key, value, expires_in: expires_in)
        serialized_value = Marshal.dump(value)
      end
      Marshal.load(serialized_value)
    end

    # Read a value from the cache.
    #
    # @param key [Object] The cache key.
    # @return [Object, nil] The cached value or nil if not found.
    def read(key)
      fetch(key)
    end

    # Write a value to the cache.
    #
    # @param key [Object] The cache key.
    # @param value [Object] The value to cache. Nil values are not cached.
    # @param expires_in [Integer, nil] Time in seconds until the cached value expires.
    # @return [void]
    def write(key, value, expires_in: nil)
      return if value.nil?

      if expires_in
        expire_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + expires_in
      end

      serialized_value = Marshal.dump(value)

      @mutex.synchronize do
        @cache[key] = [serialized_value, expire_at]
      end
    end

    # Delete a value from the cache.
    #
    # @param key [Object] The cache key.
    # @return [void]
    def delete(key)
      @cache.delete(key)
    end

    # Clear all values from the cache.
    #
    # @return [void]
    def clear
      @cache.clear
    end
  end
end
