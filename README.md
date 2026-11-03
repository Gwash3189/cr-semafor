# cr-semafor

A lightweight Crystal library for bounding concurrent work with keyed semaphores, acquisition wait timeouts, and execution time limits.

`cr-semafor` is a Crystal port of [`semafor`](https://github.com/Gwash3189/semafor), a TypeScript library for controlling how many tasks may run at once for a given key, how long callers are willing to wait to acquire a permit, and how long the guarded work may run.

## Installation

Add the shard to your `shard.yml`:

```yaml
dependencies:
  cr-semafor:
    github: Gwash3189/cr-semafor
```

Then run `shards install`.

## Usage

### Direct execution

Acquire a slot for a key and immediately run a block:

```crystal
require "cr-semafor"

result = Semafor.semafor(
  "key",
  wait: 5.seconds,
  workers: 35,
  limit: 2.5.seconds
) do |release, signal|
  begin
    do_work(signal)
  ensure
    release.call
  end
end

result.result
result.release.call
```

`release` is idempotent, so calling it from both the block's `ensure` and the returned result is safe.

### Handle API

Create a reusable handle for a key:

```crystal
handle = Semafor.semaphore("key", wait: 5.seconds, workers: 35)

result = handle.acquire do |release, signal|
  begin
    do_work(signal)
  ensure
    release.call
  end
end

handle.release
```

For compatibility with the TypeScript API, `Handle#aquire` exists as an alias for `Handle#acquire`. Prefer `acquire`.

### Configuration object

Named options can be captured in a reusable `Semafor::Config`:

```crystal
config = Semafor::Config.new(workers: 35, wait: 5.seconds, limit: 2.5.seconds)

Semafor.semafor("key", config) do |release, signal|
  begin
    do_work(signal)
  ensure
    release.call
  end
end
```

## Configuration

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `workers` | `Int32` | `1` | Maximum number of concurrent executions for the key. |
| `wait` | `Time::Span?` | `nil` | Maximum time to wait for a slot. `nil` waits indefinitely. |
| `limit` | `Time::Span?` | `nil` | Maximum time the guarded work may run. `nil` means no limit. |

Invalid configuration raises `ArgumentError`.

## Execution limits and cancellation

Crystal fibers cannot be safely force-killed, so cancellation is cooperative.

When `limit` is set, the block runs in a spawned fiber. If it exceeds the limit, the caller raises `Semafor::LimitExceededError`, releases the semaphore slot, and cancels the signal. The block may continue running until it checks the signal or returns.

Use the signal inside long-running work:

```crystal
Semafor.semafor("key", limit: 1.second) do |release, signal|
  begin
    loop do
      signal.check! # raises if the limit was exceeded
      do_chunk_of_work
    end
  ensure
    release.call
  end
end
```

The signal also supports `#cancelled?`, `#reason`, and `#on_cancel`.

## Errors

- `Semafor::Error`: base class for all semaphore errors.
- `Semafor::WaitTimeoutError`: waiting to acquire a slot exceeded `wait`.
- `Semafor::LimitExceededError`: guarded work exceeded `limit`.
- `Semafor::CancelledError`: `Signal#check!` was called on a signal cancelled without a reason.

## Development

```bash
crystal build src/cr-semafor.cr   # compile the library
crystal tool format --check src   # check formatting
```

## License

MIT. See [LICENSE](LICENSE).
