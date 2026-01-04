# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.2.0

### Changed

- Replaced thread local variables with fiber local variables to prevent behavior from leaking across fibers.

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
