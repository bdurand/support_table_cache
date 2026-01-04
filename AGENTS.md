# Copilot Instructions for support_table_cache

## Project Overview

This is a Ruby gem that adds transparent caching to ActiveRecord support/lookup tables. It intercepts `find_by` queries and `belongs_to` associations to cache small, rarely-changing reference tables (statuses, types, categories) without code changes.

**Core principle**: Cache entries keyed by unique attribute combinations, auto-invalidated on record changes via `after_commit` callbacks.

## Architecture

- **lib/support_table_cache.rb**: Main module with `cache_by` DSL, cache configuration, and invalidation logic
- **lib/support_table_cache/find_by_override.rb**: Prepends to model class to intercept `find_by` calls
- **lib/support_table_cache/relation_override.rb**: Prepends to `ActiveRecord::Relation` to handle scoped queries (e.g., `where(group: 'x').find_by(name: 'y')`)
- **lib/support_table_cache/associations.rb**: Extends `belongs_to` with `cache_belongs_to` to cache foreign key lookups
- **lib/support_table_cache/memory_cache.rb**: In-process cache implementation (use `support_table_cache = :memory`)

See [ARCHITECTURE.md](../ARCHITECTURE.md) for detailed flow diagrams showing cache key generation, invalidation, and association caching sequences.

## Key Patterns

### Model Configuration
Models use `cache_by` to declare unique keys that can be cached. Support composite keys and case-insensitivity:
```ruby
cache_by :name, case_sensitive: false
cache_by [:group, :code]
cache_by :name, where: {deleted_at: nil}  # For default scopes
```

### Cache Key Structure
Cache keys are `[ClassName, {attr1: val1, attr2: val2}]` arrays with sorted attribute names. Case-insensitive values are downcased before keying.

### Module Prepending Pattern
Uses `prepend` to wrap ActiveRecord methods (`find_by`) rather than monkey-patching. This allows `super` to call original behavior on cache misses or when caching disabled.

## Testing

- **Multi-version testing**: Uses Appraisal gem to test against ActiveRecord 5.0-8.0 (see [Appraisals](../Appraisals))
- **Run tests**: `bundle exec rspec` (default rake task) or `bundle exec appraisal rspec` for all versions
- **Test setup**: In-memory SQLite database created in [spec/spec_helper.rb](../spec/spec_helper.rb) with test tables
- **Test isolation**: Tests wrapped with `SupportTableCache.testing!` in RSpec `config.before` to prevent cache pollution

### Code Style
Use **standardrb** for linting. Run `standardrb --fix` before committing. CI enforces this on ActiveRecord 8.0 matrix entry.

## Common Operations

### Adding Cache Support to Models
1. Include `SupportTableCache` in model class
2. Call `cache_by` with unique key attributes
3. Optionally set `self.support_table_cache_ttl = 5.minutes`
4. For associations: include `SupportTableCache::Associations` in parent model, then `cache_belongs_to :association_name`

### Cache Invalidation
Automatic via `after_commit` callback that clears all cache key variations (both old and new attribute values on updates). No manual invalidation needed unless using in-memory cache across processes.

### Debugging Cache Behavior
- Use `fetch_by` instead of `find_by` to raise error if query won't hit cache
- Disable caching in block: `Model.disable_cache { ... }` or globally `SupportTableCache.disable { ... }`
- Check if caching enabled: inspect `support_table_cache_by_attributes` class attribute

## Development Workflow

1. **Running specs locally**: `bundle exec rspec` (uses Ruby 3.3+ and ActiveRecord 8.0 from Gemfile)
2. **Testing specific AR version**: `bundle exec appraisal activerecord_7 rspec`
3. **Generating all gemfiles**: `bundle exec appraisal generate`
4. **Lint before commit**: `standardrb --fix`
5. **Release**: Only from `main` branch (enforced by `Rakefile` pre-release check)

## Important Constraints

- **Target models**: Only for small tables (few hundred rows max)
- **Unique keys only**: `cache_by` attributes must define unique constraints
- **No runtime scopes**: Cannot use `cache_belongs_to` with scoped associations (checked at configuration time)
- **In-memory cache caveat**: Per-process, not invalidated across processes—only use for truly static data or with TTL
