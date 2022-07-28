# frozen_string_literal: true

if defined?(Rails::Railtie)
  module SupportTableCache
    class Railtie < Rails::Railtie
      initializer do
        SupportTableCache.cache = Rails.cache if defined?(Rails.cache)
      end
    end
  end
end
