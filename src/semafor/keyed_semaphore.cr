require "sync"

module Semafor
  module Internal
    # :nodoc:
    private class Waiter
      enum State
        Waiting
        Granted
        Cancelled
      end

      getter channel = Channel(Bool).new(1)
      property state = State::Waiting
      property lease : Lease?
    end

    # :nodoc:
    class KeyedSemaphore
      getter key : String

      def initialize(@key : String, workers : Int32 = 1)
        @max_workers = workers
        @mutex = Sync::Mutex.new
        @active = 0
        @waiters = Deque(Waiter).new
        @leases = Set(Lease).new
      end

      def active_count : Int32
        @mutex.synchronize { @active }
      end

      def pending_count : Int32
        @mutex.synchronize { @waiters.size }
      end

      def update_workers(workers : Int32) : Nil
        raise ArgumentError.new("workers must be at least 1") if workers < 1

        @mutex.synchronize do
          @max_workers = workers
          drain_locked
        end
      end

      def acquire(wait : Time::Span? = nil) : Lease
        waiter = @mutex.synchronize do
          if @active < @max_workers && @waiters.empty?
            @active += 1
            return create_lease_locked
          end

          entry = Waiter.new
          @waiters << entry
          entry
        end

        if wait
          select
          when waiter.channel.receive
            waiter.lease.not_nil!
          when timeout(wait)
            resolve_timeout(waiter, wait)
          end
        else
          waiter.channel.receive
          waiter.lease.not_nil!
        end
      end

      private def resolve_timeout(waiter : Waiter, wait : Time::Span) : Lease
        granted = @mutex.synchronize do
          if waiter.state.granted?
            waiter.lease
          else
            waiter.state = Waiter::State::Cancelled
            @waiters.delete(waiter)
            nil
          end
        end

        return granted if granted
        raise WaitTimeoutError.new(@key, wait)
      end

      private def create_lease_locked : Lease
        lease = Lease.new(@key) { |released| release_lease(released) }
        @leases.add(lease)
        lease
      end

      protected def release_lease(lease : Lease) : Nil
        @mutex.synchronize do
          return unless @leases.delete(lease)

          @active -= 1
          drain_locked
        end
      end

      def release_all : Nil
        leases = @mutex.synchronize { @leases.to_a }
        leases.each &.release
      end

      private def drain_locked : Nil
        while @active < @max_workers && (waiter = @waiters.shift?)
          next if waiter.state.cancelled?

          waiter.lease = create_lease_locked
          @active += 1
          waiter.state = Waiter::State::Granted
          waiter.channel.send(true)
        end
      end
    end
  end
end
