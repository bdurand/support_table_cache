# frozen_string_literal: true

require_relative "spec_helper"

describe SupportTableCache do
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

    it "does not use the cache when finding by a single attribute in a composite key" do
      expect(TestModel.find_by(code: "one")).to eq record_1
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(TestModel, {code: "one"}, ["code"], false))).to eq nil
    end

    it "uses the cache when finding by multiple cacheable attributes with a relation chain" do
      expect(TestModel.where(group: "First").find_by(code: "one")).to eq record_1
      expect(SupportTableCache.cache.read(SupportTableCache.cache_key(TestModel, {code: "one", group: "First"}, ["code", "group"], false))).to eq record_1

      expect(TestModel.where(group: "First").find_by(code: "one")).to eq record_1
      expect(TestModel.where(group: "Second").find_by(code: "two")).to eq record_2

      expect(TestModel.where(group: "First").find_by(code: "one").value).to eq 1
      record_1.update_columns(value: 3)
      expect(TestModel.where(group: "First").find_by(code: "one").value).to eq 1
      expect(TestModel.where(code: "one").find_by(group: "First").value).to eq 1
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
      SupportTableCache.disable do
        expect(SupportTableCache.cache).to_not receive(:fetch)
        expect(TestModel.find_by(name: "One")).to eq record_1
        expect(SupportTableCache.disabled?).to eq true
        SupportTableCache.enable do
          expect(SupportTableCache.disabled?).to eq false
        end
        expect(SupportTableCache.disabled?).to eq true
      end
      expect(SupportTableCache.disabled?).to eq false
    end

    it "can disable just for a class" do
      SupportTableCache.disable do
        TestModel.enable_caching do
          expect(SupportTableCache.disabled?).to eq false
          expect(SupportTableCache.cache).to receive(:fetch)
          expect(TestModel.find_by(name: "One")).to eq record_1
          TestModel.disable_caching do
            expect(SupportTableCache.cache).not_to receive(:fetch)
            expect(TestModel.find_by(name: "One")).to eq record_1
          end
        end
      end
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
