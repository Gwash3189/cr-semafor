require "sync"

require "./semafor/errors"
require "./semafor/config"
require "./semafor/lease"
require "./semafor/signal"
require "./semafor/result"
require "./semafor/keyed_semaphore"
require "./semafor/execution"
require "./semafor/handle"

# Bounded keyed semaphores for Crystal.
#
# `Semafor` limits how many tasks may run concurrently for a given key, how
# long callers wait to acquire a slot, and how long guarded work may run.
#
# ```
# result = Semafor.semafor("key", workers: 2, wait: 5.seconds, limit: 1.second) do |release, signal|
#   begin
#     do_work(signal)
#   ensure
#     release.call
#   end
# end
#
# result.result
# ```
module Semafor
  VERSION = "0.1.0"

  @@registry = {} of String => Internal::KeyedSemaphore
  @@registry_mutex = Sync::Mutex.new

  # Creates a reusable handle for a key.
  #
  # The `workers` option defaults to `1`. `wait` and `limit` default to `nil`.
  def self.semafor(
    key : String,
    *,
    workers : Int32 = 1,
    wait : Time::Span? = nil,
    limit : Time::Span? = nil,
  ) : Handle
    config = Config.new(workers: workers, wait: wait, limit: limit)
    Handle.new(key, config, fetch_semaphore(key, config))
  end

  # Creates a reusable handle for a key from a `Config`.
  def self.semafor(key : String, config : Config) : Handle
    Handle.new(key, config, fetch_semaphore(key, config))
  end

  # Acquires a slot for a key and runs the block.
  #
  # The block receives a `Lease` and a `Signal`. The lease is released
  # automatically if the block raises or exceeds the configured limit.
  def self.semafor(
    key : String,
    *,
    workers : Int32 = 1,
    wait : Time::Span? = nil,
    limit : Time::Span? = nil,
    &block : Lease, Signal -> T
  ) : Result(T) forall T
    config = Config.new(workers: workers, wait: wait, limit: limit)
    semaphore, lease = acquire(key, config)
    Internal::Execution(T).new(semaphore, config, lease, block).run
  end

  # Acquires a slot for a key from a `Config` and runs the block.
  def self.semafor(key : String, config : Config, &block : Lease, Signal -> T) : Result(T) forall T
    semaphore, lease = acquire(key, config)
    Internal::Execution(T).new(semaphore, config, lease, block).run
  end

  # Alias for `.semafor` that returns a reusable handle.
  def self.semaphore(
    key : String,
    *,
    workers : Int32 = 1,
    wait : Time::Span? = nil,
    limit : Time::Span? = nil,
  ) : Handle
    semafor(key, workers: workers, wait: wait, limit: limit)
  end

  # Alias for `.semafor` that returns a reusable handle.
  def self.semaphore(key : String, config : Config) : Handle
    semafor(key, config)
  end

  # Alias for `.semafor` that acquires a slot and runs the block.
  def self.semaphore(
    key : String,
    *,
    workers : Int32 = 1,
    wait : Time::Span? = nil,
    limit : Time::Span? = nil,
    &block : Lease, Signal -> T
  ) : Result(T) forall T
    semafor(key, workers: workers, wait: wait, limit: limit) do |lease, signal|
      block.call(lease, signal)
    end
  end

  # Alias for `.semafor` that acquires a slot from a `Config` and runs the block.
  def self.semaphore(key : String, config : Config, &block : Lease, Signal -> T) : Result(T) forall T
    semafor(key, config) do |lease, signal|
      block.call(lease, signal)
    end
  end

  # Clears all registered keyed semaphores.
  #
  # Existing handles and leases remain valid, but new calls create a fresh
  # semaphore for the key. This is primarily useful in tests.
  def self.reset_semaphores : Nil
    @@registry_mutex.synchronize { @@registry.clear }
  end

  private def self.acquire(key : String, config : Config) : {Internal::KeyedSemaphore, Lease}
    semaphore = fetch_semaphore(key, config)
    {semaphore, semaphore.acquire(config.wait)}
  end

  private def self.fetch_semaphore(key : String, config : Config) : Internal::KeyedSemaphore
    @@registry_mutex.synchronize do
      if semaphore = @@registry[key]?
        semaphore.update_workers(config.workers)
        semaphore
      else
        semaphore = Internal::KeyedSemaphore.new(key, config.workers)
        @@registry[key] = semaphore
        semaphore
      end
    end
  end
end
