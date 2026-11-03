module Semafor
  # A lease on a semaphore slot.
  #
  # Releasing a lease is idempotent and thread-safe. The lease can be released
  # from inside the guarded block, from the returned `Result`, or from a
  # `Handle`.
  class Lease
    # The semaphore key associated with this lease.
    getter key : String

    @released = Atomic(Bool).new(false)

    def initialize(@key : String, &@on_release : Lease -> Nil)
    end

    # Releases the semaphore slot. Calling this more than once is safe.
    def release : Nil
      return unless @released.swap(true) == false
      @on_release.call(self)
    end

    # Alias for `#release`, matching the TypeScript `release()` call style.
    def call : Nil
      release
    end

    # Returns whether this lease has already been released.
    def released? : Bool
      @released.get
    end
  end
end
