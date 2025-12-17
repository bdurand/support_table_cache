# frozen_string_literal: true

require "spec_helper"

RSpec.describe SupportTableCache::Associations do
  let!(:record) { TestModel.create!(name: "One", code: "one", group: "First", value: 1) }
  let!(:parent) { ParentModel.create!(test_model: record) }

  it "overrides the belongs_to method to use the cache" do
    parent.test_model
    TestModel.delete_all
    parent_id = parent.id
    parent = ParentModel.find(parent_id)
    expect(parent.test_model).to eq record
  end

  it "does not cache if the cache is set to nil" do
    cache = SupportTableCache.cache
    begin
      SupportTableCache.cache = nil
      expect(cache).to_not receive(:fetch)
      expect(parent.test_model).to eq record
    ensure
      SupportTableCache.cache = cache
    end
  end
end
