# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.1.6

### Fixed

- Queries on relations with conditions that cannot be represented in the cache key (SQL string conditions, ranges, `not`, `or`, joins, `group`, `having`, `from`, `offset`, locking, or non-hash `find_by` arguments) now bypass the cache instead of silently ignoring those conditions and returning or caching the wrong record.
- `create_with` values are no longer included in cache keys, so queries using `create_with` can now be cached correctly.
- Queries inside an open transaction now bypass the cache so that uncommitted data can never be cached. Previously a rolled back transaction could permanently poison the cache with data that was never committed. Transactions created with `joinable: false` (such as Rails transactional test fixtures) still use the cache.
- Cache invalidation now runs even when caching is disabled. Previously records changed inside a `disable` block (or while caching was disabled globally) left stale entries behind for when caching was re-enabled.
- Cache key values are now cast through the attribute type, so equivalent values (e.g. `:one` and `"one"`, or `"5"` and `5`) produce the same cache key. Previously such entries could be written under keys that the invalidation callbacks could never delete. This also fixes cache keys for `false` attribute values, which were previously indistinguishable from `nil`.
- `load_cache` no longer raises an error when caching is disabled and now honors `where` conditions on `cache_by` configurations instead of caching records that do not match them. It also refreshes existing cache entries instead of skipping them.
- A `cache_by` configuration whose `where` clause does not match a query no longer prevents later configurations from matching, and no longer mutates the query attributes while matching.
- Calling `cache_by` in a subclass no longer mutates the superclass's cache configuration.
- Models that include `SupportTableCache` without calling `cache_by` no longer raise an error on `find_by`.
- Calling `cache_belongs_to` more than once for the same association no longer causes infinite recursion when reading the association.
- `SupportTableCache::MemoryCache` now synchronizes all access to the underlying hash (previously reads, deletes, and clears were unsynchronized), purges expired entries, and no longer serializes values twice on a cache miss.
- `SupportTableCache::FiberLocals` now stores state in the fiber's native local storage so that state cannot leak from fibers that are garbage collected while suspended inside a block.

## 1.1.5

### Fixed

- Replaced thread local variables with fiber local variables to prevent the possibility of behavior from leaking across fibers when disabling the cache in a block.
- Allow setting the cache to an in-memory cache by setting `support_table_cache` to `true`.

## 1.1.4

### Fixed

- Fixed issue where using `find_by` on a `has_many` relation would not take the scope of the relation into account when looking up the cached record. Now chaining a `find_by` onto a `has_many` relation will correctly bypass the cache and directly query the database.

## 1.1.3

### Fixed

- Avoid calling methods that require a database connection when setting up belongs to caching.

## 1.1.2

### Fixed

- Do not cache records where only some of the columns have been loaded with a call to `select`.

## 1.1.1

### Fixed

- Fixed disabled and disable_cache methods to yield a block to match the documentation.

## 1.1.0

### Added

- Added fetch_by and fetch_by! methods that can verify the result will be cacheable.
- Allow configuring cache storage on a per class basis.
- Allow disabling caching on per class basis.
- Added optimized in-memory cache implementation.
- Added support for caching belongs to assocations.
- Added test mode to intialize new caches within a test block.

### Changed

- Changed fiber local variables used for disabling the cache to thread local variables.
- Using find_by! on a relation will now use the cache.

## 1.0.1

### Added

- Preserve scope on relations terminated with a `find_by`.

## 1.0.0

### Added

- Add SupportTableCache concern to enable automatic caching on models when calling `find_by` with unique key parameters.
