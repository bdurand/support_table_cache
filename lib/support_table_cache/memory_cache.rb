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
      # Maps a cache key to the tokens of the fetches currently generating a value for it.
      # Invalidating a key drops its tokens so that those fetches will not store the stale
      # value they generated. Only keys with a fetch in flight are tracked.
      @pending = {}
    end

    # Fetch a value from the cache. If the key is not found or has expired, yields to get a new value.
    #
    # @param key [Object] The cache key.
    # @param expires_in [Integer, nil] Time in seconds until the cached value expires.
    # @yield Block to execute to get a new value if the key is not cached.
    # @return [Object, nil] The cached value or the result of the block, or nil if no value is found.
    def fetch(key, expires_in: nil)
      serialized_value = nil
      token = nil
      @mutex.synchronize do
        cached_value, cached_expire_at = @cache[key]
        if cached_expire_at && cached_expire_at < Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @cache.delete(key)
        else
          serialized_value = cached_value
        end

        if serialized_value.nil? && block_given?
          token = Object.new
          (@pending[key] ||= []) << token
        end
      end

      if serialized_value.nil?
        begin
          value = yield if block_given?
          return nil if value.nil?

          serialized_value = Marshal.dump(value)
          # The expiration is always recalculated from the expires_in argument so that replacing
          # an expired entry without an expiration does not carry over the old expiration time.
          expire_at = (Process.clock_gettime(Process::CLOCK_MONOTONIC) + expires_in if expires_in)

          @mutex.synchronize do
            # Only store the value if this key was not invalidated while the value was being
            # generated. Otherwise a record deleted or overwritten by a concurrent update could
            # be resurrected in the cache with stale data.
            @cache[key] = [serialized_value, expire_at] if @pending[key]&.include?(token)
          end
        ensure
          @mutex.synchronize do
            tokens = @pending[key]
            if tokens
              tokens.delete(token)
              @pending.delete(key) if tokens.empty?
            end
          end
        end
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
        # Discard any fetch generating a value for this key so that it cannot overwrite the
        # newer value being written here.
        @pending.delete(key)
        @cache[key] = [serialized_value, expire_at]
      end

      nil
    end

    # Delete a value from the cache.
    #
    # @param key [Object] The cache key.
    # @return [void]
    def delete(key)
      @mutex.synchronize do
        @pending.delete(key)
        @cache.delete(key)
      end
      nil
    end

    # Clear all values from the cache.
    #
    # @return [void]
    def clear
      @mutex.synchronize do
        @pending.clear
        @cache.clear
      end
      nil
    end
  end
end
