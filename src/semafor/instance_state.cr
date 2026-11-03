require "sync"

module Semafor
  # :nodoc:
  #
  # Tracks leases acquired by a single object. Leases are tracked per fiber so
  # nested acquisitions on the same object release in LIFO order.
  class InstanceState
    def initialize
      @mutex = Sync::Mutex.new
      @leases_by_fiber = {} of Fiber => Array(Lease)
      @lease_fibers = {} of Lease => Fiber
      @started_leases = Set(Lease).new
      @abandoned_leases = Set(Lease).new
    end

    def track(lease : Lease) : Nil
      fiber = Fiber.current
      @mutex.synchronize do
        # A timeout can end the acquisition before the execution fiber starts.
        # Do not leave a late tracking entry behind.
        return if @abandoned_leases.delete(lease)

        @started_leases.add(lease)
        @lease_fibers[lease] = fiber
        (@leases_by_fiber[fiber] ||= [] of Lease) << lease
      end
    end

    def untrack(lease : Lease) : Nil
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

    def current_lease : Lease?
      @mutex.synchronize do
        @leases_by_fiber[Fiber.current]?.try &.last?
      end
    end

    def release_current : Lease?
      @mutex.synchronize do
        if leases = @leases_by_fiber[Fiber.current]?
          released = leases.pop?
          @lease_fibers.delete(released) if released
          @leases_by_fiber.delete(Fiber.current) if leases.empty?
          released
        end
      end
    end
  end
end
