# frozen_string_literal: true

require "spec_helper"

RSpec.describe SupportTableCache::FiberLocals do
  let(:fiber_locals) { described_class.new }

  describe "#[]" do
    it "returns nil for unset keys" do
      expect(fiber_locals[:foo]).to be_nil
    end

    it "returns nil for keys from other fibers" do
      fiber_locals.with(:foo, :bar) do
        # Set in this fiber
      end

      # Access from main fiber should return nil
      expect(fiber_locals[:foo]).to be_nil
    end

    it "is fiber-isolated" do
      fiber_locals.with(:key, :main_value) do
        result = nil
        fiber = Fiber.new do
          fiber_locals.with(:key, :fiber_value) do
            result = fiber_locals[:key]
          end
        end
        fiber.resume

        expect(result).to eq(:fiber_value)
        expect(fiber_locals[:key]).to eq(:main_value)
      end
    end
  end

  describe "#with" do
    it "sets a value for the duration of the block" do
      expect(fiber_locals[:key]).to be_nil

      fiber_locals.with(:key, :value) do
        expect(fiber_locals[:key]).to eq(:value)
      end

      expect(fiber_locals[:key]).to be_nil
    end

    it "returns the block's return value" do
      result = fiber_locals.with(:key, :value) do
        "returned value"
      end

      expect(result).to eq("returned value")
    end

    it "restores previous value after block" do
      fiber_locals.with(:key, :first) do
        expect(fiber_locals[:key]).to eq(:first)

        fiber_locals.with(:key, :second) do
          expect(fiber_locals[:key]).to eq(:second)
        end

        expect(fiber_locals[:key]).to eq(:first)
      end

      expect(fiber_locals[:key]).to be_nil
    end

    it "supports nested with blocks for different keys" do
      fiber_locals.with(:key1, :value1) do
        expect(fiber_locals[:key1]).to eq(:value1)
        expect(fiber_locals[:key2]).to be_nil

        fiber_locals.with(:key2, :value2) do
          expect(fiber_locals[:key1]).to eq(:value1)
          expect(fiber_locals[:key2]).to eq(:value2)
        end

        expect(fiber_locals[:key1]).to eq(:value1)
        expect(fiber_locals[:key2]).to be_nil
      end
    end

    it "restores previous value even on exception" do
      expect {
        fiber_locals.with(:key, :value) do
          raise "boom"
        end
      }.to raise_error("boom")

      expect(fiber_locals[:key]).to be_nil
    end

    it "cleans up fiber locals when first initialized in a fiber" do
      fiber = Fiber.new do
        fiber_locals.with(:key, :value) do
          expect(fiber_locals[:key]).to eq(:value)
        end
        # After the block, locals should be cleaned up
        expect(fiber_locals[:key]).to be_nil
      end

      fiber.resume
    end

    it "is thread-safe" do
      threads = 10.times.map do |i|
        Thread.new do
          fiber_locals.with(:thread_key, "thread_#{i}") do
            sleep(0.001)
            expect(fiber_locals[:thread_key]).to eq("thread_#{i}")
          end
        end
      end

      threads.each(&:join)
    end

    it "handles multiple fibers in the same thread" do
      results = []

      fiber1 = Fiber.new do
        fiber_locals.with(:key, :fiber1_value) do
          results << fiber_locals[:key]
          Fiber.yield
          results << fiber_locals[:key]
        end
      end

      fiber2 = Fiber.new do
        fiber_locals.with(:key, :fiber2_value) do
          results << fiber_locals[:key]
          Fiber.yield
          results << fiber_locals[:key]
        end
      end

      fiber1.resume
      fiber2.resume
      fiber1.resume
      fiber2.resume

      expect(results).to eq([:fiber1_value, :fiber2_value, :fiber1_value, :fiber2_value])
    end

    it "handles nil values" do
      fiber_locals.with(:key, :initial) do
        expect(fiber_locals[:key]).to eq(:initial)

        fiber_locals.with(:key, nil) do
          expect(fiber_locals[:key]).to be_nil
        end

        expect(fiber_locals[:key]).to eq(:initial)
      end
    end

    it "handles false values" do
      fiber_locals.with(:key, false) do
        expect(fiber_locals[:key]).to eq(false)
      end

      expect(fiber_locals[:key]).to be_nil
    end

    it "supports various key types" do
      fiber_locals.with(:symbol_key, :value1) do
        expect(fiber_locals[:symbol_key]).to eq(:value1)
      end

      fiber_locals.with("string_key", :value2) do
        expect(fiber_locals["string_key"]).to eq(:value2)
      end

      fiber_locals.with(123, :value3) do
        expect(fiber_locals[123]).to eq(:value3)
      end
    end

    it "does not leak memory across fibers" do
      initial_locals_count = fiber_locals.instance_variable_get(:@locals).size

      100.times do
        Fiber.new do
          fiber_locals.with(:key, :value) do
            # Use the value
          end
        end.resume
      end

      # Locals should be cleaned up for completed fibers
      final_locals_count = fiber_locals.instance_variable_get(:@locals).size
      expect(final_locals_count).to be <= initial_locals_count + 1
    end
  end

  describe "fiber isolation" do
    it "maintains separate values per fiber" do
      main_result = nil
      fiber_result = nil

      fiber_locals.with(:shared_key, :main_value) do
        main_result = fiber_locals[:shared_key]

        fiber = Fiber.new do
          fiber_locals.with(:shared_key, :fiber_value) do
            fiber_result = fiber_locals[:shared_key]
          end
        end
        fiber.resume

        # Main fiber value should be unchanged
        expect(fiber_locals[:shared_key]).to eq(:main_value)
      end

      expect(main_result).to eq(:main_value)
      expect(fiber_result).to eq(:fiber_value)
    end
  end
end
