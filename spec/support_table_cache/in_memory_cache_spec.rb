# frozen_string_literal: true

require_relative "../spec_helper"

describe SupportTableCache::InMemoryCache do
  let(:cache) { SupportTableCache::InMemoryCache.new }

  # rubocop:disable Style/RedundantFetchBlock
  it "caches values" do
    value = cache.fetch("foo") { :bar }
    expect(value).to eq :bar

    cached_value = cache.fetch("foo") { raise "boom" }
    expect(cached_value).to eq :bar
  end

  it "expires values" do
    value = cache.fetch("foo", expires_in: 0.01) { :bar }
    expect(value).to eq :bar

    cached_value = cache.fetch("foo") { :baz }
    expect(cached_value).to eq :bar

    sleep(0.02)

    new_value = cache.fetch("foo") { :baq }
    expect(new_value).to eq :baq
  end

  it "does not cache nil" do
    value = cache.fetch("foo") { nil }
    expect(value).to eq nil

    cached_value = cache.fetch("foo") { :bar }
    expect(cached_value).to eq :bar
  end

  it "deletes values" do
    cache.fetch("foo") { :bar }
    cache.delete("foo")
    value = cache.fetch("foo") { :baz }
    expect(value).to eq :baz
  end

  it "clears the cache" do
    cache.fetch("foo") { :bar }
    cache.clear
    value = cache.fetch("foo") { :baz }
    expect(value).to eq :baz
  end

  # rubocop:enable Style/RedundantFetchBlock
end
