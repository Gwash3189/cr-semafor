module Semafor
  # Configuration for a keyed semaphore.
  #
  # - `workers` is the maximum number of concurrent executions for a key.
  # - `wait` is how long an acquisition may wait in the queue. `nil` waits
  #   indefinitely.
  # - `limit` is how long guarded work may run. `nil` means no execution limit.
  struct Config
    # Maximum number of concurrent executions.
    getter workers : Int32

    # Maximum time to wait for a slot, or `nil` to wait indefinitely.
    getter wait : Time::Span?

    # Maximum execution time for guarded work, or `nil` for no limit.
    getter limit : Time::Span?

    def initialize(@workers : Int32 = 1, @wait : Time::Span? = nil, @limit : Time::Span? = nil)
      raise ArgumentError.new("workers must be at least 1") if @workers < 1

      if wait = @wait
        raise ArgumentError.new("wait must be a non-negative duration") if wait < Time::Span.zero
      end

      if limit = @limit
        raise ArgumentError.new("limit must be a non-negative duration") if limit < Time::Span.zero
      end
    end
  end
end
