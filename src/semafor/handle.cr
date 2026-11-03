module Semafor
  # A reusable handle for a keyed semaphore.
  #
  # A handle remembers the configuration used to create it and tracks leases it
  # has acquired so they can be released together.
  class Handle
    # The semaphore key.
    getter key : String

    # The configuration used by this handle.
    getter config : Config

    def initialize(@key : String, @config : Config, @semaphore : Internal::KeyedSemaphore)
      @mutex = Sync::Mutex.new
      @leases = Set(Lease).new
    end

    # Acquires a slot and runs the block.
    #
    # The block receives a `Lease` and a `Signal`. The lease is safe to release
    # more than once.
    def acquire(&block : Lease, Signal -> T) : Result(T) forall T
      lease = @semaphore.acquire(@config.wait)
      register(lease)
      Internal::Execution(T).new(@semaphore, @config, lease, block).run
    end

    # Compatibility alias for the TypeScript API's `aquire` typo.
    #
    # Prefer `#acquire`.
    def aquire(&block : Lease, Signal -> T) : Result(T) forall T
      acquire { |lease, signal| block.call(lease, signal) }
    end

    # Releases leases acquired through this handle.
    #
    # If the handle has not acquired any leases, all leases for the key are
    # released, matching the TypeScript behavior.
    def release : Nil
      leases = @mutex.synchronize do
        current = @leases.to_a
        @leases.clear
        current
      end

      if leases.empty?
        @semaphore.release_all
      else
        leases.each &.release
      end
    end

    # Number of currently active slots for the key.
    def active_count : Int32
      @semaphore.active_count
    end

    # Number of callers waiting for a slot for the key.
    def pending_count : Int32
      @semaphore.pending_count
    end

    private def register(lease : Lease) : Nil
      @mutex.synchronize do
        @leases.reject!(&.released?)
        @leases.add(lease)
      end
    end
  end
end
