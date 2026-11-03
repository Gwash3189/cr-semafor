require "benchmark"
require "../src/cr-semafor"

semaphore = Semafor.new("benchmark", workers: 8)

Benchmark.bm do |benchmark|
  benchmark.report("instance acquire/release") do
    10_000.times do
      semaphore.acquire { }
    end
  end

  benchmark.report("shared direct acquire/release") do
    10_000.times do
      Semafor.semafor("benchmark-direct", workers: 1) do |release, _signal|
        release.call
      end
    end
  end
end
