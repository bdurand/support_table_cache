# Support Table Cache

[![Continuous Integration]()
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)

This gem adds caching for ActiveRecord support table models. These are models which have a unique key (i.e. a unique `name` attribute, etc.) and which have a limited number of entries (a few hundred at most). These are often models added do normalize the data structure.

Rows from these kinds of tables are rarely inserted, updated, or deleted, but are queried very frequently. To take advantage of this behavior, this gem adds automatic caching for records when using the `find_by` method. This is most useful in situations where you have a unique key but need to get the database row for that key.

For instance, suppose you have a model `Status` that has a unique name attribute and processes that pass in that status using the name and you then need to get the id for the status to query for records:

```ruby
status = Status.find_by(name: params[:status]
results = Things.where(status_id: status.id)
```

With this gem, you can avoid the database query for the `find_by` call. You don't need to alter your code in any way other than to include `SupportTableCache` in your model and tell it which attributes comprise a unique key that can be used for caching.

Admittedly, that won't save you much in this situation, since it's a single database query. However, if you have code like that in a loop, it can save you quite a bit of load on the database.

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

If you are in a Rails application, the `Rails.cache` will be used by default to cache records. Otherwise, you need to set the `ActiveSupport::Cache::CacheStore`` to use.

```ruby
SupportTableCache.cache = ActiveSupport::Cache::MemoryStore.new
```

You can also disable caching behavior entirely if you want or just within a block. You may want to disable it entirely in test mode if it interferes with your tests.

```ruby
# Disable the cache globally
SupportTableCache.disable

SupportTableCache.enable do
  # Re-enable the cache for the block
  SupportTableCache.disable do
    # Disable it again
  end
end
```

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
