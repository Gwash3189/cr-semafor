module Semafor
  # Releases the permit associated with the current fiber's most recent
  # acquisition on this object.
  #
  # This method is available on classes that `include Semafor` and use the
  # `semafor` declaration macro.
  #
  # Raises `Semafor::Error` when the current fiber has no active acquisition.
  def release : Lease
    __semafor_state.current_lease || raise Error.new("No active semaphore acquisition for this fiber")
  end

  private def __semafor_state : InstanceState
    @__semafor_state ||= InstanceState.new
  end

  private def __semafor_execute(
    key : Symbol | String,
    *,
    workers : Int32 = 1,
    wait : Time::Span? = nil,
    limit : Time::Span? = nil,
    &block : Lease, Signal -> T
  ) : T forall T
    config = Config.new(workers: workers, wait: wait, limit: limit)
    semaphore = Semafor.__semaphore_for(key.to_s, config)
    lease = semaphore.acquire(config.wait)

    on_start = ->(started_lease : Lease) do
      __semafor_state.track(started_lease)
      nil
    end

    tracked_block = ->(tracked_lease : Lease, signal : Signal) do
      begin
        block.call(tracked_lease, signal)
      ensure
        __semafor_state.untrack(tracked_lease)
      end
    end

    begin
      Internal::Execution(T).new(semaphore, config, lease, tracked_block, on_start).run.result
    ensure
      lease.release
      # On a limit timeout the execution fiber may still be running. Leave
      # tracking intact so a late `release.call` remains a safe no-op.
      __semafor_state.untrack(lease) unless config.limit
    end
  end

  # Declares that a public instance method should run inside a keyed semaphore.
  #
  # The declaration must appear before the method definition:
  #
  # ```
  # class A
  #   include Semafor
  #
  #   semafor key: :work, workers: 2, method: :perform
  #
  #   def perform
  #     begin
  #       do_work
  #     ensure
  #       release.call
  #     end
  #   end
  # end
  # ```
  #
  # Keys are shared through the global registry, so different classes using the
  # same key share the same worker limit.
  macro semafor(*, key, wait = nil, workers = 1, limit = nil, method)
    {% config_name = "SEMAFOR_CONFIG_" + method.stringify.gsub(/[^A-Za-z0-9_]/, "_").upcase %}
    {{config_name.id}} = {
      key: {{key}},
      wait: {{wait}},
      workers: {{workers}},
      limit: {{limit}},
      method: {{method}},
    }
  end

  macro included
    # `Semafor.new` is a module factory. Including this module would otherwise
    # make `SomeClass.new` resolve to it, so restore normal constructors.
    def self.new(*args, **options)
      instance = allocate
      instance.initialize(*args, **options)
      instance
    end

    def self.new(*args, **options, &block)
      instance = allocate
      instance.initialize(*args, **options, &block)
      instance
    end

    macro method_added(a_def)
      \{% config = nil %}
      \{% for constant in @type.constants %}
        \{% if constant.stringify.starts_with?("SEMAFOR_CONFIG_") %}
          \{% candidate = @type.constant(constant) %}
          \{% if candidate[:method].id.stringify == a_def.name.stringify %}
            \{% config = candidate %}
          \{% end %}
        \{% end %}
      \{% end %}
      \{% if config %}
        \{% if a_def.abstract? %}
          \{% raise "semafor: cannot wrap abstract method '#{a_def.name}'" %}
        \{% end %}
        \{% if a_def.visibility.id.stringify != "public" %}
          \{% raise "semafor: can only wrap public instance methods, '#{a_def.name}' is #{a_def.visibility}" %}
        \{% end %}
        \{% signature_parts = [] of StringLiteral %}
        \{% private_signature_parts = [] of StringLiteral %}
        \{% positional_parts = [] of StringLiteral %}
        \{% named_parts = [] of StringLiteral %}
        \{% splat_index = a_def.splat_index %}
        \{% for arg, index in a_def.args %}
          \{% if splat_index && index == splat_index && arg.name.stringify.empty? %}
            \{% signature_parts << "*" %}
            \{% private_signature_parts << "*" %}
          \{% elsif splat_index && index == splat_index %}
            \{% signature_parts << "*#{arg}" %}
            \{% private_signature_parts << "*#{arg}" %}
            \{% positional_parts << "*#{arg.internal_name}" %}
          \{% elsif splat_index && index > splat_index %}
            \{% signature_parts << "#{arg}" %}
            \{% private_signature_parts << "#{arg}" %}
            \{% named_parts << "#{arg.name}: #{arg.internal_name}" %}
          \{% else %}
            \{% signature_parts << "#{arg}" %}
            \{% private_signature_parts << "#{arg}" %}
            \{% positional_parts << "#{arg.internal_name}" %}
          \{% end %}
        \{% end %}
        \{% double_splat = a_def.double_splat %}
        \{% double_splat_part = nil %}
        \{% unless double_splat.is_a?(Nop) %}
          \{% signature_parts << "**#{double_splat.name}" %}
          \{% private_signature_parts << "**#{double_splat.name}" %}
          \{% double_splat_part = "**#{double_splat.internal_name}" %}
        \{% end %}
        \{% block_part = nil %}
        \{% if a_def.accepts_block? %}
          \{% block_arg = a_def.block_arg %}
          \{% if block_arg.is_a?(Arg) && !block_arg.restriction.is_a?(Nop) %}
            \{% signature_parts << "&__semafor_block : #{block_arg.restriction}" %}
            \{% private_signature_parts << "&#{block_arg}" %}
            \{% block_part = "&__semafor_block" %}
          \{% else %}
            \{% raise "semafor: wrapped method '#{a_def.name}' must use a named, type-restricted block argument" %}
          \{% end %}
        \{% end %}
        \{% call_parts = positional_parts %}
        \{% if double_splat_part %}
          \{% call_parts << double_splat_part %}
        \{% end %}
        \{% for named_part in named_parts %}
          \{% call_parts << named_part %}
        \{% end %}
        \{% if block_part %}
          \{% call_parts << block_part %}
        \{% end %}
        \{% original_name = "__semafor_original_" + a_def.name.id.stringify.gsub(/[^A-Za-z0-9_]/, "_") + "_" + "#{@type.methods.size}" %}
        private def \{{original_name.id}}(\{{private_signature_parts.join(", ").id}})
          \{{a_def.body}}
        end

        def \{{a_def.name}}(\{{signature_parts.join(", ").id}})
          __semafor_execute(
            \{{config[:key]}},
            workers: \{{config[:workers]}},
            wait: \{{config[:wait]}},
            limit: \{{config[:limit]}}
          ) do
            \{{original_name.id}}(\{{call_parts.join(", ").id}})
          end
        end
      \{% end %}
    end
  end
end
