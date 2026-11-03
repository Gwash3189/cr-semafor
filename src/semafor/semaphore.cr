module Semafor
  # An independent, block-scoped semaphore instance.
  #
  # Unlike `Semafor.semaphore`, an instance is not registered globally. Every
  # `Semafor::Semaphore` owns its own worker pool.
  #
  # ```
  # semaphore = Semafor.new(workers: 2, wait: 5.seconds)
  #
  # semaphore.acquire do
  #   do_work
  # ensure
  #   semaphore.release
  # end
  # ```
  class Semaphore
    # The label used for this semaphore in error messages.
    getter key : String

    # The configuration for this instance.
    getter config : Config

    def initialize(
      @key : String = "semafor",
      *,
      workers : Int32 = 1,
      wait : Time::Span? = nil,
      limit : Time::Span? = nil,
    )
      @config = Config.new(workers: workers, wait: wait, limit: limit)
      @semaphore = Internal::KeyedSemaphore.new(@key, @config.workers)
      @state = InstanceState.new
    end

    def initialize(@key : String, @config : Config)
      @semaphore = Internal::KeyedSemaphore.new(@key, @config.workers)
      @state = InstanceState.new
    end

    # Acquires a permit and runs the block.
    #
    # The block receives a `Lease` and a `Signal`; zero-argument blocks are also
    # supported. The permit is released automatically when the block exits,
    # including on exceptions and limit timeouts.
    #
    # Calling `#release` from inside the block releases the permit early.
    def acquire(&block : Lease, Signal -> T) : T forall T
      lease = @semaphore.acquire(@config.wait)
      on_start = ->(started_lease : Lease) do
        @state.track(started_lease)
        nil
      end

      begin
        Internal::Execution(T).new(@semaphore, @config, lease, block, on_start).run.result
      ensure
        lease.release
        @state.untrack(lease)
      end
    end

    # Releases the permit associated with the current fiber's most recent
    # acquisition.
    #
    # Does nothing when the current fiber has no tracked acquisition.
    def release : Nil
      @state.release_current.try &.release
    end

    # Number of currently active permits.
    def active_count : Int32
      @semaphore.active_count
    end

    # Number of callers waiting for a permit.
    def pending_count : Int32
      @semaphore.pending_count
    end
  end
end
