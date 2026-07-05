# frozen_string_literal: true

require "spec_helper"

RSpec.describe SupportTableCache do
  let!(:record_1) { TestModel.create!(name: "One", code: "one", group: "First", value: 1) }
  let!(:record_2) { TestModel.create!(name: "Two", code: "two", group: "Second", value: 2) }

  describe "cache key" do
    it "generates a consistent cache key for a set of attributes" do
      key_1 = SupportTableCache.cache_key(TestModel, {group: "first", code: "one"}, ["code", "group"], true)
      key_2 = SupportTableCache.cache_key(TestModel, {code: "one", group: "first"}, ["code", "group"], true)
      expect(key_1).to eq key_2
      expect(key_1).to eq ["TestModel", {"code" => "one", "group" => "first"}]
    end

    it "generates a case sensitive cache key for a set of attributes" do
      key_1 = SupportTableCache.cache_key(TestModel, {group: "first", code: "one"}, ["code", "group"], false)
      key_2 = SupportTableCache.cache_key(TestModel, {code: "ONE", group: "FIRST"}, ["code", "group"], false)
      key_3 = SupportTableCache.cache_key(TestModel, {code: "ONE", group: "FIRST"}, ["code", "group"], true)
      expect(key_1).to eq key_2
      expect(key_1).to_not eq key_3
    end

    it "returns nil if the attributes do not match" do
      key = SupportTableCache.cache_key(TestModel, {group: "first", code: "one"}, ["code", "name"], false)
      expect(key).to eq nil
    end

    it "normalizes equivalent attribute values to the same cache key" do
      expect(SupportTableCache.cache_key(TestModel, {name: :One}, ["name"], true))
        .to eq SupportTableCache.cache_key(TestModel, {name: "One"}, ["name"], true)
      expect(SupportTableCache.cache_key(TestModel, {value: "1"}, ["value"], true))
        .to eq SupportTableCache.cache_key(TestModel, {value: 1}, ["value"], true)
    end
  end

  describe "cache_by" do
    it "can remove existing caching by calling with false" do
      expect(TestModel.support_table_cache_by_attributes.size).to eq 2
      expect(Subclass.support_table_cache_by_attributes.size).to eq 1
    end

    it "does not modify the parent class configuration when a subclass overrides it" do
      parent_config = TestModel.support_table_cache_by_attributes.dup
      Class.new(TestModel) do
        cache_by :name, case_sensitive: false
      end
      expect(TestModel.support_table_cache_by_attributes).to eq parent_config
    end
  end

  describe "finding" do
    it "uses the cache if querying by a cacheable attributes" do
      expect(TestModel.find_by(name: "One")).to eq record_1
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(TestModel, {name: "One"}, ["name"], true))).to eq record_1

      expect(TestModel.find_by(name: "One")).to eq record_1
      expect(TestModel.find_by(name: "Two")).to eq record_2

      expect(TestModel.find_by(name: "One").value).to eq 1
      record_1.update_columns(value: 3)
      expect(TestModel.find_by(name: "One").value).to eq 1
    end

    it "uses the cache when finding by multiple cacheable attributes" do
      expect(TestModel.find_by(code: "one", group: "First")).to eq record_1
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(TestModel, {code: "one", group: "First"}, ["code", "group"], false))).to eq record_1

      expect(TestModel.find_by(code: "one", group: "First")).to eq record_1
      expect(TestModel.find_by(code: "two", group: "Second")).to eq record_2

      expect(TestModel.find_by(code: "one", group: "First").value).to eq 1
      record_1.update_columns(value: 3)
      expect(TestModel.find_by(code: "one", group: "First").value).to eq 1
      expect(TestModel.find_by(group: "First", code: "one").value).to eq 1
    end

    it "uses the cache when using find_by!" do
      expect(TestModel.find_by!(name: "One")).to eq record_1
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(TestModel, {name: "One"}, ["name"], true))).to eq record_1
    end

    it "raises and error when using find_by! and the record doesn't exist" do
      expect { TestModel.find_by!(name: "Not Exist") }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "does not use the cache when finding by a single attribute in a composite key" do
      expect(TestModel.find_by(code: "one")).to eq record_1
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(TestModel, {code: "one"}, ["code"], false))).to eq nil
    end

    it "does not use the cache when finding by a non-cacheable attribute" do
      expect(SupportTableCache.cache).to receive(:fetch).and_return(:value)
      expect(TestModel.find_by(name: "One")).to eq :value

      expect(SupportTableCache.cache).to receive(:fetch).and_return(:other_value)
      expect(TestModel.find_by(code: "one", group: "First")).to eq :other_value

      expect(SupportTableCache.cache).to_not receive(:fetch)
      expect(TestModel.find_by(value: 1)).to eq record_1
      expect(TestModel.find_by(name: "One", value: 1)).to eq record_1
    end

    it "does not use the cache when find_by is called with non-hash arguments" do
      expect(TestModel.find_by(name: "One")).to eq record_1 # prime the cache
      expect(TestModel.find_by("value > 100")).to be_nil
    end

    it "does not error on a model that includes the concern without any cache_by" do
      thing = NoCacheByModel.create!(name: "no cache by")
      expect(NoCacheByModel.find_by(name: "no cache by")).to eq thing
    end

    it "invalidates entries created with equivalent attribute values" do
      TestModel.support_table_cache = :memory
      begin
        expect(TestModel.find_by(name: :One).value).to eq 1
        record_1.update!(value: 42)
        expect(TestModel.find_by(name: :One).value).to eq 42
        expect(TestModel.find_by(name: "One").value).to eq 42
      ensure
        TestModel.support_table_cache = nil
      end
    end
  end

  describe "finding on a relation" do
    it "uses the cache when finding by multiple cacheable attributes with a relation chain" do
      expect(TestModel.where(group: "First").find_by(code: "one")).to eq record_1
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(TestModel, {code: "one", group: "First"}, ["code", "group"], false))).to eq record_1

      expect(TestModel.where(group: "First").find_by(code: "one")).to eq record_1
      expect(TestModel.where(group: "Second").find_by(code: "two")).to eq record_2
      expect(TestModel.where(group: "Second").find_by(code: "one")).to be_nil

      expect(TestModel.where(group: "First").find_by(code: "one").value).to eq 1
      record_1.update_columns(value: 3)
      expect(TestModel.where(group: "First").find_by(code: "one").value).to eq 1
      expect(TestModel.where(code: "one").find_by(group: "First").value).to eq 1
    end

    it "does not use the cache when finding on an association" do
      thing = Thing.create!(name: "Thing One")
      OtherThing.create!(thing: thing, test_model: record_1)

      TestModel.find_by(name: "One") # prime the cache
      TestModel.find_by(name: "Two") # prime the cache

      expect(thing.test_models.find_by(name: "One")).to eq record_1
      expect(thing.test_models.find_by(name: "Two")).to be_nil
    end

    it "uses the cache when finding by multiple cacheable attributes with a relation chain with find_by!" do
      expect(TestModel.where(group: "First").find_by!(code: "one")).to eq record_1
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(TestModel, {code: "one", group: "First"}, ["code", "group"], false))).to eq record_1
    end

    it "raises an error when using find_by! on a relation and the record doesn't exist" do
      expect { TestModel.where(group: "First").find_by!(code: "not exist") }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "does not use the cache when finding by a non-cacheable attribute" do
      expect(SupportTableCache.cache).to_not receive(:fetch)
      expect(TestModel.where(group: "First").find_by(value: 1)).to eq record_1
    end

    it "does not use the cache when only some of the columns are selected" do
      expect(TestModel.select(:id, :name).find_by(name: "One")).to eq record_1
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(TestModel, {name: "One"}, ["name"], true))).to eq nil
    end

    it "does not use the cache when the relation has conditions that cannot be represented in the cache key" do
      expect(TestModel.find_by(name: "One")).to eq record_1 # prime the cache
      expect(TestModel.where("value > 100").find_by(name: "One")).to be_nil
      expect(TestModel.where(value: 100..200).find_by(name: "One")).to be_nil
      expect(TestModel.where.not(value: 1).find_by(name: "One")).to be_nil
      expect(TestModel.where(name: "One").find_by("value > 100")).to be_nil
    end

    it "does not populate the cache from a relation with conditions not in the cache key" do
      cache_key = SupportTableCache.cache_key(TestModel, {name: "One"}, ["name"], true)
      expect(TestModel.where("value > 100").find_by(name: "One")).to be_nil
      expect(SupportTableCache.cache.read(cache_key)).to be_nil
    end

    it "ignores create_with values when building the cache key" do
      expect(TestModel.create_with(value: 100).where(group: "First").find_by(code: "one")).to eq record_1
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(TestModel, {code: "one", group: "First"}, ["code", "group"], false))).to eq record_1
    end
  end

  describe "finding inside a transaction" do
    it "does not use or populate the cache inside a transaction" do
      cache_key = SupportTableCache.cache_key(TestModel, {name: "One"}, ["name"], true)
      TestModel.transaction do
        expect(TestModel.find_by(name: "One")).to eq record_1
      end
      expect(SupportTableCache.cache.read(cache_key)).to be_nil
    end

    it "does not cache uncommitted data from a rolled back transaction" do
      TestModel.transaction do
        record_1.update!(value: 500)
        expect(TestModel.find_by(name: "One").value).to eq 500
        raise ActiveRecord::Rollback
      end
      expect(record_1.reload.value).to eq 1
      expect(TestModel.find_by(name: "One").value).to eq 1
    end

    it "uses the cache inside a non-joinable transaction like transactional test fixtures" do
      cache_key = SupportTableCache.cache_key(TestModel, {name: "One"}, ["name"], true)
      TestModel.connection.transaction(joinable: false) do
        expect(TestModel.find_by(name: "One")).to eq record_1
      end
      expect(SupportTableCache.cache.read(cache_key)).to eq record_1
    end
  end

  describe "finding with a where condition on the cache configuration" do
    it "uses the cache for a config declared after a config with a non-matching where clause" do
      record = WhereConditionModel.create!(name: "n1", label: "l1")
      expect(WhereConditionModel.find_by(label: "l1")).to eq record
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(WhereConditionModel, {label: "l1"}, ["label"], true))).to eq record
    end
  end

  describe "finding with a default scope" do
    it "can ignore a default scope for caching" do
      record = DefaultScopeModel.create!(name: "one")
      expect(DefaultScopeModel.find_by(name: "one")).to eq record
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(DefaultScopeModel, {name: "one"}, ["name"], true))).to eq record
    end

    it "can ignore a scope for caching" do
      record = DefaultScopeModel.create!(name: "one")
      expect(DefaultScopeModel.unscoped.where(deleted_at: nil).find_by(name: "one")).to eq record
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(DefaultScopeModel, {name: "one"}, ["name"], true))).to eq record
    end

    it "does not ignore the scope if it doesn't match" do
      time = Time.at(Time.now.to_i)
      record = DefaultScopeModel.create!(name: "one", deleted_at: time)
      expect(DefaultScopeModel.unscoped.where(deleted_at: time).find_by(name: "one")).to eq record
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(DefaultScopeModel, {name: "one"}, ["name"], true))).to eq nil
    end
  end

  describe "fetching" do
    it "fetches records by attributes" do
      expect(TestModel.fetch_by(name: "One")).to eq record_1
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(TestModel, {name: "One"}, ["name"], true))).to eq record_1
    end

    it "fetches scoped records by attributes" do
      expect(TestModel.where(group: "First").fetch_by(code: "one")).to eq record_1
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(TestModel, {code: "one", group: "First"}, ["code", "group"], false))).to eq record_1
    end

    it "fetches scoped records by attributes with an empty scope" do
      expect(TestModel.readonly.fetch_by(name: "One")).to eq record_1
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(TestModel, {name: "One"}, ["name"], true))).to eq record_1
    end

    it "raises an ArgumentError if fetched query is not cacheable" do
      expect { TestModel.fetch_by(code: "one") }.to raise_error(ArgumentError)
    end

    it "raises an ArgumentError if scoped fetched query is not cacheable" do
      expect { TestModel.where(value: nil).fetch_by(code: "one") }.to raise_error(ArgumentError)
    end

    it "raises an ActiveRecord::RecordNotFoundError if fetch_by! does not find a record" do
      expect(TestModel.fetch_by!(name: "One")).to eq record_1
      expect { TestModel.fetch_by!(name: "Not Exist") }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "raises an ActiveRecord::RecordNotFoundError if scoped fetch_by! does not find a record" do
      expect(TestModel.where(group: "First").fetch_by!(code: "one")).to eq record_1
      expect { TestModel.where(group: "First").fetch_by!(code: "Not Exist") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "clearing the cache" do
    it "can uncache a cached entry" do
      expect(TestModel.find_by(name: "One", code: "one").value).to eq 1
      expect(TestModel.find_by(name: "One").value).to eq 1
      expect(TestModel.find_by(code: "one").value).to eq 1
      record_1.update_columns(value: 3)
      record_1.uncache
      expect(TestModel.find_by(name: "One", code: "one").value).to eq 3
      expect(TestModel.find_by(name: "One").value).to eq 3
      expect(TestModel.find_by(code: "one").value).to eq 3
    end

    it "clears cache entries a record is updated" do
      expect(TestModel.find_by(name: "One").value).to eq 1
      record_1.update!(value: 3)
      expect(TestModel.find_by(name: "One").value).to eq 3
    end

    it "clears cache entries a cacheable attribute is updated" do
      expect(TestModel.find_by(name: "One")).to eq record_1
      record_1.update!(name: "New One")
      expect(TestModel.find_by(name: "One")).to eq nil
      expect(TestModel.find_by(name: "New One")).to eq record_1
    end

    it "clears cache entries when a record is created" do
      expect(TestModel.find_by(name: "Three")).to eq nil
      expect(TestModel.find_by(name: "Three", code: "three")).to eq nil
      record_3 = TestModel.create!(name: "Three", code: "three", value: 3)
      expect(TestModel.find_by(name: "Three")).to eq record_3
      expect(TestModel.find_by(name: "Three")).to eq record_3
    end

    it "clears cache entries when a record is destroyed" do
      expect(TestModel.find_by(name: "One")).to eq record_1
      expect(TestModel.find_by(name: "One", code: "one")).to eq record_1
      record_1.destroy
      expect(TestModel.find_by(name: "One")).to eq nil
    end

    it "clears case insensitive cache entries a record is updated" do
      expect(TestModel.find_by(code: "one", group: "First").value).to eq 1
      record_1.update_columns(code: "ONE", group: "FIRST")
      record_1.reload
      record_1.update!(value: 3)
      expect(TestModel.find_by(name: "One").value).to eq 3
    end
  end

  describe "disabling" do
    it "can disable caching in a block" do
      disabled = []
      disabled_value = SupportTableCache.disable do
        expect(SupportTableCache.cache).to_not receive(:fetch)
        expect(TestModel.find_by(name: "One")).to eq record_1
        disabled << SupportTableCache.disabled?

        enabled_value = SupportTableCache.enable do
          disabled << SupportTableCache.disabled?
          :enabled_retval
        end
        expect(enabled_value).to eq :enabled_retval

        disabled << SupportTableCache.disabled?
        :disabled_retval
      end
      expect(disabled_value).to eq :disabled_retval
      expect(disabled).to eq [true, false, true]
      expect(SupportTableCache.disabled?).to eq false
    end

    it "can disable just for a class" do
      blocks_executed = false
      SupportTableCache.disable do
        enabled_value = TestModel.enable_cache do
          expect(SupportTableCache.cache).to receive(:fetch).and_call_original
          expect(TestModel.find_by(name: "One")).to eq record_1

          disabled_value = TestModel.disable_cache do
            expect(SupportTableCache.cache).not_to receive(:fetch)
            expect(TestModel.find_by(name: "One")).to eq record_1
            blocks_executed = true
            :disabled_retval
          end
          expect(disabled_value).to eq :disabled_retval

          :enabled_retval
        end

        expect(enabled_value).to eq :enabled_retval
      end

      expect(blocks_executed).to eq true
    end

    it "still clears cache entries when a record is changed while caching is disabled" do
      expect(TestModel.find_by(name: "One").value).to eq 1
      SupportTableCache.disable do
        record_1.update!(value: 42)
      end
      expect(TestModel.find_by(name: "One").value).to eq 42
    end
  end

  describe "setting the cache" do
    it "does not cache if the cache is nil" do
      cache = SupportTableCache.cache
      begin
        SupportTableCache.cache = nil
        expect(cache).to_not receive(:fetch)
        expect(TestModel.find_by(name: "One")).to eq record_1
      ensure
        SupportTableCache.cache = cache
      end
    end

    it "can set a cache per class" do
      cache = ActiveSupport::Cache::MemoryStore.new
      TestModel.support_table_cache = cache
      save_cache = SupportTableCache.cache
      SupportTableCache.cache = nil
      begin
        expect(cache).to receive(:fetch).twice.and_call_original
        expect(TestModel.find_by(name: "One")).to eq record_1
        expect(TestModel.find_by(name: "One")).to eq record_1
      ensure
        SupportTableCache.cache = save_cache
        TestModel.support_table_cache = nil
      end
    end

    it "can set the cache to an in memory cache" do
      save_cache = SupportTableCache.cache
      begin
        SupportTableCache.cache = :memory
        expect(SupportTableCache.cache).to be_a(SupportTableCache::MemoryCache)
        expect(SupportTableCache.cache.object_id).to_not eq save_cache.object_id
      ensure
        SupportTableCache.cache = save_cache
      end
    end

    it "can set a cache per class to an in memory cache" do
      TestModel.support_table_cache = :memory
      expect(TestModel.send(:support_table_cache_impl)).to be_a(SupportTableCache::MemoryCache)
    ensure
      TestModel.support_table_cache = nil
    end

    it "can set the cache to an in memory cache using true" do
      TestModel.support_table_cache = true
      expect(TestModel.send(:support_table_cache_impl)).to be_a(SupportTableCache::MemoryCache)
    ensure
      TestModel.support_table_cache = nil
    end
  end

  describe "loading the cache" do
    it "loads the cache with all records" do
      cache = ActiveSupport::Cache::MemoryStore.new
      TestModel.support_table_cache = cache
      begin
        TestModel.load_cache
      ensure
        TestModel.support_table_cache = nil
      end

      [
        [record_1, {"name" => "One"}, ["name"], true],
        [record_1, {"code" => "one", "group" => "First"}, ["code", "group"], false],
        [record_2, {"name" => "Two"}, ["name"], true],
        [record_2, {"code" => "two", "group" => "Second"}, ["code", "group"], false]
      ].each do |record, attributes, attribute_names, case_sensitive|
        cache_key = SupportTableCache.cache_key(TestModel, attributes, attribute_names, case_sensitive)
        expect(cache.read(cache_key)).to eq record
      end
    end

    it "does nothing when caching is disabled" do
      expect { SupportTableCache.disable { TestModel.load_cache } }.to_not raise_error
    end

    it "does not cache records that do not match a where condition" do
      active = WhereConditionModel.create!(name: "active-one")
      deleted = WhereConditionModel.create!(name: "deleted-one", deleted_at: Time.now)
      cache = ActiveSupport::Cache::MemoryStore.new
      WhereConditionModel.support_table_cache = cache
      begin
        WhereConditionModel.load_cache
        expect(cache.read(SupportTableCache.cache_key(WhereConditionModel, {name: "active-one"}, ["name"], true))).to eq active
        expect(cache.read(SupportTableCache.cache_key(WhereConditionModel, {name: "deleted-one"}, ["name"], true))).to be_nil
        expect(deleted.reload.name).to eq "deleted-one"
      ensure
        WhereConditionModel.support_table_cache = nil
      end
    end
  end

  describe "testing!" do
    it "initializes new caches within a block" do
      normal_cache = SupportTableCache.cache

      SupportTableCache.testing! do
        testing_cache = SupportTableCache.cache
        expect(testing_cache).to be_a(SupportTableCache::MemoryCache)
        expect(testing_cache).to_not eq normal_cache

        SupportTableCache.testing! do
          expect(SupportTableCache.cache).to eq testing_cache
        end
      end

      expect(SupportTableCache.cache).to eq normal_cache
    end
  end
end
