require "./spec_helper"

class WrappedDirect
  include Semafor

  semafor key: :module_wrapped_direct, wait: 100.milliseconds, workers: 1, method: :work

  def work(value : Int32) : Int32
    begin
      value * 2
    ensure
      release.call
    end
  end
end

class WrappedAutoRelease
  include Semafor

  semafor key: :module_wrapped_auto, wait: 100.milliseconds, workers: 1, method: :work

  def work
    "done"
  end
end

class WrappedSharedKey
  include Semafor

  semafor key: :module_shared, wait: 10.milliseconds, workers: 1, method: :work

  def work
    "shared"
  end
end

class WrappedArguments
  include Semafor

  semafor key: :module_args_positional, method: :positional
  semafor key: :module_args_named, method: :named
  semafor key: :module_args_splat, method: :splatted
  semafor key: :module_args_block, method: :blocked

  def positional(value : Int32, suffix : String = "!")
    "#{value}#{suffix}"
  end

  def named(value : Int32, *, suffix : String = "!")
    "#{value}#{suffix}"
  end

  def splatted(value : Int32, *rest, suffix : String = "!", **options)
    "#{value}-#{rest}-#{suffix}-#{options}"
  end

  def blocked(value : Int32, &block : Int32 -> String)
    block.call(value)
  end
end

class WrappedOverload
  include Semafor

  semafor key: :module_overload, method: :work

  def work(value : Int32)
    "int:#{value}"
  end

  def work(value : String)
    "string:#{value}"
  end
end

class WrappedWithInitialize
  include Semafor

  semafor key: :module_initialize, method: :work

  def initialize(@prefix : String)
  end

  def work(value : Int32)
    "#{@prefix}#{value}"
  end
end

class WrappedError
  include Semafor

  semafor key: :module_error, wait: 100.milliseconds, method: :work

  def work
    raise "wrapped boom"
  end
end

class WrappedNoReturn
  include Semafor

  semafor key: :module_noreturn, wait: 100.milliseconds, method: :work

  def work
    raise "always raises"
  end
end

class WrappedNested
  include Semafor

  semafor key: :module_nested_outer, workers: 2, method: :outer
  semafor key: :module_nested_inner, workers: 2, method: :inner

  def outer
    inner
    release.call
    "outer"
  end

  def inner
    "inner"
  ensure
    release.call
  end
end

class WrappedLimit
  include Semafor

  semafor key: :module_limit, wait: 100.milliseconds, limit: 10.milliseconds, method: :work

  def work
    sleep 100.milliseconds
    "done"
  end
end

class WrappedLimitEnsure
  include Semafor

  semafor key: :module_limit_ensure, wait: 100.milliseconds, limit: 10.milliseconds, method: :work

  def work(done : Channel(Bool))
    begin
      sleep 50.milliseconds
    ensure
      release.call
      done.send(true)
    end
  end
end

describe "Semafor module inclusion" do
  describe "a wrapped method" do
    it "runs the method and releases the permit" do
      result = WrappedDirect.new.work(21)

      result.should eq(42)
    end

    it "releases the permit when the method omits release" do
      result = WrappedAutoRelease.new.work

      result.should eq("done")
    end

    it "releases the permit when the method raises" do
      expect_raises(Exception, "wrapped boom") do
        WrappedError.new.work
      end

      ran = false
      Semafor.semafor("module_error", wait: 100.milliseconds) do |release, _signal|
        ran = true
        release.call
      end

      ran.should be_true
    end

    it "supports a method that always raises" do
      expect_raises(Exception, "always raises") do
        WrappedNoReturn.new.work
      end
    end

    it "supports nested wrapped methods" do
      result = WrappedNested.new.outer

      result.should eq("outer")
    end

    it "supports overloaded wrapped methods" do
      subject = WrappedOverload.new

      subject.work(1).should eq("int:1")
      subject.work("one").should eq("string:one")
    end

    it "preserves class constructors" do
      WrappedWithInitialize.new("value:").work(1).should eq("value:1")
    end
  end

  describe "global key sharing" do
    it "shares the worker limit with the keyed registry" do
      held = Semafor.semafor("module_shared", workers: 1) { |_release, _signal| "held" }

      expect_raises(Semafor::WaitTimeoutError) do
        WrappedSharedKey.new.work
      end

      held.release.call
    end
  end

  describe "method arguments" do
    it "forwards positional and default arguments" do
      WrappedArguments.new.positional(1, "?").should eq("1?")
    end

    it "forwards named arguments" do
      WrappedArguments.new.named(1, suffix: "?").should eq("1?")
    end

    it "forwards splat and double-splat arguments" do
      WrappedArguments.new.splatted(1, 2, 3, suffix: "?", extra: 4).should eq("1-{2, 3}-?-{extra: 4}")
    end

    it "forwards block arguments" do
      WrappedArguments.new.blocked(3) { |value| "got #{value}" }.should eq("got 3")
    end
  end

  describe "execution limits" do
    it "raises LimitExceededError and releases the permit" do
      expect_raises(Semafor::LimitExceededError) do
        WrappedLimit.new.work
      end

      ran = false
      Semafor.semafor("module_limit", wait: 100.milliseconds) do |release, _signal|
        ran = true
        release.call
      end

      ran.should be_true
    end

    it "allows release.call from a late ensure after a limit timeout" do
      done = Channel(Bool).new(1)

      expect_raises(Semafor::LimitExceededError) do
        WrappedLimitEnsure.new.work(done)
      end

      receive_within(done, 1.second).should be_true
    end
  end

  describe "#release" do
    it "raises when there is no active acquisition" do
      expect_raises(Semafor::Error, "No active semaphore acquisition for this fiber") do
        WrappedDirect.new.release
      end
    end
  end
end
