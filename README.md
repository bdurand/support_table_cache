# Support Table Cache

[![Continuous Integration](https://github.com/bdurand/support_table_cache/actions/workflows/continuous_integration.yml/badge.svg)](https://github.com/bdurand/support_table_cache/actions/workflows/continuous_integration.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)

This gem adds caching for ActiveRecord support table models. These are models which have a unique key (i.e. a unique `name` attribute, etc.) and which have a limited number of entries (a few hundred at most). These are often models added do normalize the data structure.

Rows from these kinds of tables are rarely inserted, updated, or deleted, but are queried very frequently. To take advantage of this behavior, this gem adds automatic caching for records when using the `find_by` method. This is most useful in situations where you have a unique key but need to get the database row for that key.

For instance, suppose you have a model `Status` that has a unique name attribute and you need to process a bunch of records from a data source that includes the status name. In order to do anything, you'll need to lookup each status by name to get the database id:

```ruby
params.each do |data|
  status = Status.find_by(name: data[:status]
  Things.where(id: data[:id]).update!(status_id: status.id)
end
```

With this gem, you can avoid the database query for the `find_by` call. You don't need to alter your code in any way other than to include `SupportTableCache` in your model and tell it which attributes comprise a unique key that can be used for caching.

## Usage

To use the gem, you need to include it in you models and then specify which attributes can be used for caching with the `cache_by` method. A caching attribute must be a unique key on the model. For a composite key, you can specify an array of attributes. If any of the attributes are case insensitive strings, you need to specify that as well.

```ruby
  class MyModel < ApplicationRecord
    include SupportTableCache

    cache_by :id
    cache_by [:group, :name], case_sensitive: false
  end

  # Uses cache
  MyModel.find_by(id: 1)

  # Uses cache on a composite key
  MyModel.find_by(group: "first", name: "One")

  # Uses cache on a composite key with scoping
  MyModel.where(group: "first").find_by(name: "One")

  # Does not use cache since value is not defined as a cacheable key
  MyModel.find_by(value: 1)

  # Does not use caching since not using find_by
  MyModel.where(id: 1).first
```

By default, records will be cleaned up from the cache only when they are modified. However, you can set a time to live on the model after which records will be removed from the cache.

```ruby
  class MyModel < ApplicationRecord
    include SupportTableCache

    self.support_table_cache_ttl = 5.minutes
  end
```

If you are in a Rails application, the `Rails.cache` will be used by default to cache records. Otherwise, you need to set the `ActiveSupport::Cache::CacheStore` to use.

```ruby
SupportTableCache.cache = ActiveSupport::Cache::MemoryStore.new
```

You can also set a cache per class. You could do this, for instance, to set an in memory cache on models that will never change to avoid a network round trip to the cache server. You can use the special value `:memory` to do this.

```ruby
  class MyModel < ApplicationRecord
    include SupportTableCache

    self.support_table_cache = :memory
  end
```

You can disable the cache within a block either globally or only for a specific class. If the cache is disabled, then all queries will pass through to the database.

```ruby
# Disable the cache globally
SupportTableCache.disable

SupportTableCache.enable do
  # Re-enable the cache for the block
  SupportTableCache.disable do
    # Disable it again
    MySupportModel.enable_cache do
      # Enable it only for the MySupportModel class
    end
  end
end
```

### Belongs To Associations

You can cache belongs to assocations to cacheable models by including the `SupportTableCache::Associations` module and then calling `cache_belongs_to` to specify which associations should be cached.

The target class for the association must include the `SupportTableCache` module.

```ruby
class ParentModel <  ApplicationRecord
  include SupportTableCache::Associations

  belongs_to :my_model
  cache_belongs_to :my_model
end
```

### Testing

Caching may interfere with tests by allowing data created in one test to leak into subsequent tests. You can resolve this by wrapping your tests with the `SupportTableCache.testing!` method.

```
# Rspec
RSpec.configure do |config|
  config.around do |example|
    SupportTableCache.testing! { example.run }
  end
end

# MiniTest (with the minitest-around gem)
class Minitest::Spec
  around do |tests|
    SupportTableCache.testing!(&tests)
  end
=end

```

### Maintaining Data

You can use the companion [support_table_data gem](https://github.com/bdurand/support_table_data) to add support for loading static data into your support tables as well as adding some useful helper functions.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "support_table_cache"
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install support_table_cache
```

## Contributing

Open a pull request on [GitHub](https://github.com/bdurand/support_table_cache).

Please use the [standardrb](https://github.com/testdouble/standard) syntax and lint your code with `standardrb --fix` before submitting.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
