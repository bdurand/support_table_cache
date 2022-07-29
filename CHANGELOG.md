# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

## 1.0.1

### Added
- Preserve scope on relations terminated with a `find_by`.

## 1.0.0

### Added
- Add SupportTableCache concern to enable automatic caching on models when calling `find_by` with unique key parameters.
