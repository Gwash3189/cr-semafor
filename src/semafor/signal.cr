module Semafor
  # A cooperative cancellation signal passed to guarded work.
  #
  # Crystal fibers cannot be safely force-killed, so cancellation is
  # cooperative. Long-running work should periodically call `#check!` or inspect
  # `#cancelled?`.
  class Signal
    @mutex = Sync::Mutex.new
    @cancelled = false
    @reason : Exception? = nil
    @callbacks = [] of ->

    # Returns whether the signal has been cancelled.
    def cancelled? : Bool
      @mutex.synchronize { @cancelled }
    end

    # Returns the exception associated with cancellation, if one was provided.
    def reason : Exception?
      @mutex.synchronize { @reason }
    end

    # Cancels the signal. Calling this more than once has no additional effect.
    #
    # Cancellation callbacks run outside the internal lock. Exceptions raised by
    # callbacks are ignored so they cannot prevent the semaphore slot from being
    # released.
    def cancel!(reason : Exception? = nil) : Nil
      callbacks = [] of ->
      @mutex.synchronize do
        return if @cancelled

        @cancelled = true
        @reason = reason
        callbacks = @callbacks
        @callbacks = [] of ->
      end

      callbacks.each do |callback|
        begin
          callback.call
        rescue
          # Cancellation is best-effort; a listener must not block release.
        end
      end
    end

    # Registers a callback to run when the signal is cancelled.
    #
    # If the signal is already cancelled, the callback runs immediately.
    def on_cancel(&block : ->) : Nil
      run_now = @mutex.synchronize do
        if @cancelled
          true
        else
          @callbacks << block
          false
        end
      end

      block.call if run_now
    end

    # Raises the cancellation reason, or `CancelledError` if none was provided.
    def check! : Nil
      @mutex.synchronize do
        if reason = @reason
          raise reason
        elsif @cancelled
          raise CancelledError.new("Semaphore work was cancelled")
        end
      end
    end
  end
end
