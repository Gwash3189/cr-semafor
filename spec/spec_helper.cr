require "spec"
require "../src/cr-semafor"

def receive_within(channel : Channel(T), limit : Time::Span = 1.second) : T forall T
  select
  when value = channel.receive
    value
  when timeout(limit)
    raise "Timed out waiting for a channel value"
  end
end

def expect_no_value(channel : Channel(T), limit : Time::Span = 50.milliseconds) : Nil forall T
  select
  when value = channel.receive
    raise "Expected no value, but received #{value.inspect}"
  when timeout(limit)
  end
end
