require "./spec_helper"

describe Semafor do
  describe ".new" do
    it "creates an independent semaphore with named options" do
      semaphore = Semafor.new("instance", workers: 3, wait: 1.second, limit: 2.seconds)

      semaphore.should be_a(Semafor::Semaphore)
      semaphore.key.should eq("instance")
      semaphore.config.workers.should eq(3)
      semaphore.config.wait.should eq(1.second)
      semaphore.config.limit.should eq(2.seconds)
    end

    it "creates an independent semaphore from a config" do
      config = Semafor::Config.new(workers: 2, wait: 1.second)
      semaphore = Semafor.new(config, "configured")

      semaphore.key.should eq("configured")
      semaphore.config.should eq(config)
    end

    it "uses a default key when none is provided" do
      config = Semafor::Config.new(workers: 2)
      semaphore = Semafor.new(config)

      semaphore.key.should eq("semafor")
    end
  end

  describe "#acquire" do
    it "returns the block value" do
      semaphore = Semafor.new("return-value")

      value = semaphore.acquire { 42 }

      value.should eq(42)
    end

    it "yields a lease and a signal" do
      semaphore = Semafor.new("yields")
      lease_key = ""
      signal_cancelled = true

      semaphore.acquire do |lease, signal|
        lease_key = lease.key
        signal_cancelled = signal.cancelled?
      end

      lease_key.should eq("yields")
      signal_cancelled.should be_false
    end

    it "releases the permit automatically when the block exits" do
      semaphore = Semafor.new("auto-release", workers: 1, wait: 100.milliseconds)
      ran = false

      semaphore.acquire { }
      semaphore.acquire { ran = true }

      ran.should be_true
    end

    it "supports ensure directly in the block" do
      semaphore = Semafor.new("ensure-block", workers: 1, wait: 100.milliseconds)
      ran = false

      semaphore.acquire do
        ran = true
      ensure
        semaphore.release
      end

      ran.should be_true
      semaphore.active_count.should eq(0)
    end

    it "releases the permit when the block raises" do
      semaphore = Semafor.new("raising", workers: 1, wait: 100.milliseconds)
      ran = false

      expect_raises(Exception, "boom") do
        semaphore.acquire { raise "boom" }
      end

      semaphore.acquire { ran = true }

      ran.should be_true
    end

    it "releases the permit when the execution limit is exceeded" do
      semaphore = Semafor.new("limited", workers: 1, wait: 100.milliseconds, limit: 10.milliseconds)
      ran = false

      expect_raises(Semafor::LimitExceededError) do
        semaphore.acquire { sleep 100.milliseconds }
      end

      semaphore.acquire { ran = true }

      ran.should be_true
    end

    it "supports nested acquisitions" do
      semaphore = Semafor.new("nested", workers: 2, wait: 100.milliseconds)
      inner_ran = false
      active_after_inner = 0

      semaphore.acquire do
        semaphore.acquire do
          inner_ran = true
        end
        active_after_inner = semaphore.active_count
      end

      inner_ran.should be_true
      active_after_inner.should eq(1)
      semaphore.active_count.should eq(0)
    end
  end

  describe "#release" do
    it "releases the current acquisition early" do
      semaphore = Semafor.new("early-release", workers: 1, wait: 100.milliseconds)

      semaphore.acquire do
        semaphore.release
        semaphore.active_count.should eq(0)
      end
    end

    it "is idempotent" do
      semaphore = Semafor.new("idempotent")

      semaphore.acquire do
        semaphore.release
        semaphore.release
      end

      semaphore.active_count.should eq(0)
    end

    it "does nothing when there is no active acquisition" do
      semaphore = Semafor.new("no-active")

      semaphore.release

      semaphore.active_count.should eq(0)
    end
  end

  describe "independent instances" do
    it "does not share permits between instances" do
      first = Semafor.new("first", workers: 1)
      second = Semafor.new("second", workers: 1)
      first_started = Channel(Nil).new(1)
      release_first = Channel(Nil).new(1)
      first_done = Channel(Nil).new(1)
      second_ran = false

      spawn do
        first.acquire do
          first_started.send(nil)
          release_first.receive
        end
        first_done.send(nil)
      end

      first_started.receive
      second.acquire { second_ran = true }
      release_first.send(nil)
      receive_within(first_done)

      second_ran.should be_true
    end

    it "limits concurrency to the configured worker count" do
      semaphore = Semafor.new("bounded", workers: 2, wait: 1.second)
      started = Channel(Int32).new(3)
      gate = Channel(Nil).new
      done = Channel(Nil).new(3)

      3.times do |index|
        spawn do
          semaphore.acquire do
            started.send(index)
            gate.receive
          end
          done.send(nil)
        end
      end

      receive_within(started)
      receive_within(started)
      expect_no_value(started, 50.milliseconds)

      gate.send(nil)
      gate.send(nil)
      receive_within(started)
      gate.send(nil)

      3.times { receive_within(done) }
      semaphore.active_count.should eq(0)
    end
  end
end
