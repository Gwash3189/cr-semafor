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
      @mutex = Sync::Mutex.new
      @leases_by_fiber = {} of Fiber => Array(Lease)
      @lease_fibers = {} of Lease => Fiber
      @started_leases = Set(Lease).new
      @abandoned_leases = Set(Lease).new
    end

    def initialize(@key : String, @config : Config)
      @semaphore = Internal::KeyedSemaphore.new(@key, @config.workers)
      @mutex = Sync::Mutex.new
      @leases_by_fiber = {} of Fiber => Array(Lease)
      @lease_fibers = {} of Lease => Fiber
      @started_leases = Set(Lease).new
      @abandoned_leases = Set(Lease).new
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
        track(started_lease)
        nil
      end

      begin
        Internal::Execution(T).new(@semaphore, @config, lease, block, on_start).run.result
      ensure
        lease.release
        untrack(lease)
      end
    end

    # Releases the permit associated with the current fiber's most recent
    # acquisition.
    #
    # Does nothing when the current fiber has no tracked acquisition.
    def release : Nil
      lease = @mutex.synchronize do
        if leases = @leases_by_fiber[Fiber.current]?
          released = leases.pop?
          @lease_fibers.delete(released) if released
          @leases_by_fiber.delete(Fiber.current) if leases.empty?
          released
        end
      end

      lease.try &.release
    end

    # Number of currently active permits.
    def active_count : Int32
      @semaphore.active_count
    end

    # Number of callers waiting for a permit.
    def pending_count : Int32
      @semaphore.pending_count
    end

    private def track(lease : Lease) : Nil
      fiber = Fiber.current
      @mutex.synchronize do
        # A timeout can end the acquisition before the worker fiber starts.
        # Do not leave a late tracking entry behind.
        return if @abandoned_leases.delete(lease)

        @started_leases.add(lease)
        @lease_fibers[lease] = fiber
        (@leases_by_fiber[fiber] ||= [] of Lease) << lease
      end
    end

    private def untrack(lease : Lease) : Nil
      @mutex.synchronize do
        if fiber = @lease_fibers.delete(lease)
          if leases = @leases_by_fiber[fiber]?
            leases.delete(lease)
            @leases_by_fiber.delete(fiber) if leases.empty?
          end
          @started_leases.delete(lease)
        elsif !@started_leases.delete(lease)
          @abandoned_leases.add(lease)
        end
      end
    end
  end
end
