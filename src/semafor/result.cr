module Semafor
  # The result of a successful semaphore execution.
  #
  # `release` can be used to force release the acquired slot from outside the
  # guarded block.
  struct Result(T)
    # The value returned by the guarded block.
    getter result : T

    # The lease for the acquired slot.
    getter release : Lease

    def initialize(@result : T, @release : Lease)
    end
  end
end
