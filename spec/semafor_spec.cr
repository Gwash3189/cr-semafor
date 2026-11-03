require "./spec_helper"

describe Semafor do
  describe ".semafor" do
    context "when called with a block" do
      it "returns the block value and lease" do
        result = Semafor.semafor("direct-result", workers: 1) do |release, _signal|
          release.call
          "completed"
        end

        result.result.should eq("completed")
        result.release.released?.should be_true
      end

      it "releases the slot when the block raises" do
        expect_raises(Exception, "boom") do
          Semafor.semafor("direct-error") { raise "boom" }
        end

        ran = false
        Semafor.semafor("direct-error", wait: 100.milliseconds) do |release, _signal|
          ran = true
          release.call
        end

        ran.should be_true
      end
    end

    context "when the wait timeout is exceeded" do
      it "raises WaitTimeoutError" do
        held = Semafor.semafor("direct-wait", workers: 1) { |_release, _signal| "held" }

        expect_raises(Semafor::WaitTimeoutError) do
          Semafor.semafor("direct-wait", wait: 10.milliseconds) do |release, _signal|
            release.call
          end
        end

        held.release.call
      end
    end

    context "when the execution limit is exceeded" do
      it "raises LimitExceededError and releases the slot" do
        expect_raises(Semafor::LimitExceededError) do
          Semafor.semafor("direct-limit", limit: 10.milliseconds) { sleep 100.milliseconds }
        end

        ran = false
        Semafor.semafor("direct-limit", wait: 100.milliseconds) do |release, _signal|
          ran = true
          release.call
        end

        ran.should be_true
      end
    end
  end

  describe ".semaphore" do
    it "returns a handle that can acquire and release" do
      handle = Semafor.semaphore("handle-api", workers: 1, wait: 100.milliseconds)

      result = handle.acquire do |release, _signal|
        release.call
        "handled"
      end

      result.result.should eq("handled")
    end
  end

  describe ".reset_semaphores" do
    it "clears the registry" do
      held = Semafor.semafor("reset-api", workers: 1) { |_release, _signal| "held" }

      Semafor.reset_semaphores

      ran = false
      Semafor.semafor("reset-api", wait: 100.milliseconds) do |release, _signal|
        ran = true
        release.call
      end

      ran.should be_true
      held.release.call
    end
  end
end
