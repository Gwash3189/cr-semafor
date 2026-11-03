module Semafor
  module Internal
    # :nodoc:
    record Success(T), value : T

    # :nodoc:
    record Failure, error : Exception

    # :nodoc:
    class Execution(T)
      def initialize(
        @semaphore : KeyedSemaphore,
        @config : Config,
        @lease : Lease,
        @block : Proc(Lease, Signal, T),
        @on_start : Proc(Lease, Nil)? = nil,
      )
      end

      def run : Result(T)
        signal = Signal.new

        if limit = @config.limit
          run_with_limit(signal, limit)
        else
          run_without_limit(signal)
        end
      end

      private def run_without_limit(signal : Signal) : Result(T)
        @on_start.try &.call(@lease)

        begin
          return Result(T).new(@block.call(@lease, signal), @lease)
        rescue error
          @lease.release
          raise error
        end
      end

      private def run_with_limit(signal : Signal, limit : Time::Span) : Result(T)
        outcomes = Channel(Success(T) | Failure).new(1)

        spawn do
          begin
            @on_start.try &.call(@lease)
            outcomes.send(Success(T).new(@block.call(@lease, signal)))
          rescue error
            outcomes.send(Failure.new(error))
          end
        end

        select
        when outcome = outcomes.receive
          case outcome
          when Success
            return Result(T).new(outcome.value, @lease)
          when Failure
            @lease.release
            raise outcome.error
          end
        when timeout(limit)
          error = LimitExceededError.new(@semaphore.key, limit)
          signal.cancel!(error)
          @lease.release
          raise error
        end

        raise "unreachable"
      end
    end
  end
end
