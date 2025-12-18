# frozen_string_literal: true

require "spec_helper"

RSpec.describe SupportTableCache::MemoryCache do
  let(:cache) { SupportTableCache::MemoryCache.new }

  # rubocop:disable Style/RedundantFetchBlock
  it "fetches cached values" do
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

  it "reads, writes, and deletes values" do
    cache.write("foo", :bar)
    expect(cache.fetch("foo")).to eq :bar
    expect(cache.read("foo")).to eq :bar
    cache.delete("foo")
    expect(cache.read("foo")).to eq nil
  end

  it "clears the cache" do
    cache.fetch("foo") { :bar }
    cache.clear
    value = cache.fetch("foo") { :baz }
    expect(value).to eq :baz
  end

  # rubocop:enable Style/RedundantFetchBlock
end
