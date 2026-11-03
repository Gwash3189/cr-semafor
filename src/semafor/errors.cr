module Semafor
  # Base class for all semaphore errors.
  class Error < Exception
  end

  # Raised when a caller waits longer than the configured `wait` duration
  # without acquiring a semaphore slot.
  class WaitTimeoutError < Error
    # The semaphore key that timed out.
    getter key : String

    # The configured wait duration.
    getter wait : Time::Span

    def initialize(@key : String, @wait : Time::Span)
      super("Timed out waiting #{Semafor.format_duration(@wait)} to acquire semaphore \"#{@key}\"")
    end
  end

  # Raised when guarded work runs longer than the configured `limit`.
  class LimitExceededError < Error
    # The semaphore key whose work exceeded the limit.
    getter key : String

    # The configured execution limit.
    getter limit : Time::Span

    def initialize(@key : String, @limit : Time::Span)
      super("Semaphore \"#{@key}\" work exceeded execution limit of #{Semafor.format_duration(@limit)} and was canceled")
    end
  end

  # Raised by `Signal#check!` when a signal was cancelled without a reason.
  class CancelledError < Error
  end

  # :nodoc:
  def self.format_duration(span : Time::Span) : String
    milliseconds = span.total_milliseconds
    value = milliseconds == milliseconds.round ? milliseconds.to_i.to_s : milliseconds.to_s
    "#{value}ms"
  end
end
