defmodule Beethoven.Allocator.Agent do
  @moduledoc """
  Behaviour to define signals via the `signal()` macro.

  This macro defines a signal that can be sent to the `Beethoven.Allocator` stack.
  Once defined, this module will have compile-time created functions to streamline the use of the signal.
  Each signal has an atomic name, priority weight, and type defined in it.
  This data is aggregated and used to generate a busy-score for a node.

  # Types
  - `:count` Counts the number of a given thing. Generates 2 functions.
  One to increment the counter, the other to decrement it. Both modify the counter by `+/-1.0`.
  The counter will never be lower then `0`.

  - `:percent` Represents a float between 0.0 and >100.0. This generates 1 function.
  This function allows you to set a float payload in the signal.
  This value must be a positive float.

  # Examples
      defmodule Signals do
        use Beethoven.Allocator.Agent

        signal(name: :ram, weight: 10.0, type: :percent)
        signal(name: :http_requests, weight: 5.0, type: :count)
      end

      # Generates
      Signals.percent_ram(data) # Data is now the value of the metric in `:ets`
      Signals.increment_http_requests_count() # +1.0
      Signals.decrement_http_requests_count() # -1.0

  See `Beethoven.Allocator.Cruncher` for information on how the signals are aggregated.

  """
  alias Beethoven.Allocator
  alias Beethoven.Allocator.Types

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  # UNIQUE TYPES
  #

  #
  @typedoc """
  Defines types of signal that can be used.
  """
  @type signal_type() :: Types.signal_type()

  #
  @typedoc """
  Defines a single signal. Commonly used as an input for the `signal()` macro.
  """
  @type signal_definition() :: Types.signal_definition()

  #
  @typedoc """
  Message wrapper for sending payload to `Beethoven.Allocator.Ingress`.
  """
  @type signal_message() :: Types.signal_message()

  #
  @typedoc """
  Header for the signal metadata; when sending a signal to `Beethoven.Allocator.Ingress`.
  """
  @type signal_message_header() :: Types.signal_message_header()

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # use macro
  #

  defmacro __using__(_opts) do
    quote do
      #
      import Beethoven.Allocator.Agent
      #
    end
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Generate func(s)
  #

  #
  # generate signal functions
  @doc """
  This macro defines a signal that can be sent to the `Beethoven.Allocator` stack.
  Once defined, this module will have compile-time created functions to streamline the use of the signal.
  Each signal has an atomic name, priority weight, and type defined in it.
  This data is aggregated and used to generate a busy-score for a node.

  # Types
  - `:count` Counts the number of a given thing. Generates 2 functions.
  One to increment the counter, the other to decrement it. Both modify the counter by `+/-1.0`.
  The counter will never be lower then `0`.

  - `:percent` Represents a float between 0.0 and >100.0. This generates 1 function.
  This function allows you to set a float payload in the signal.
  This value must be a positive float.

  # Examples
      defmodule Signals do
        use Beethoven.Allocator.Agent

        signal(name: :ram, weight: 10.0, type: :percent)
        signal(name: :http_requests, weight: 5.0, type: :count)
      end

      # Generates
      Signals.percent_ram(data) # Data is now the value of the metric in `:ets`
      Signals.increment_http_requests_count() # +1.0
      Signals.decrement_http_requests_count() # -1.0

  See `Beethoven.Allocator.Cruncher` for information on how the signals are aggregated.

  """
  @spec signal(name: atom(), weight: float(), type: :count | :percent) :: tuple()
  defmacro signal(name: name, weight: weight, type: type) do
    # create func(s) based on the type
    case type do
      # Creates 2 fun for count
      :count ->
        quote do
          #
          #
          @spec unquote(String.to_atom("increment_#{name}_count"))() :: :ok
          def unquote(String.to_atom("increment_#{name}_count"))() do
            send_signal({{unquote(name), unquote(weight), unquote(type)}, 1.0})
          end

          #
          #
          @spec unquote(String.to_atom("decrement_#{name}_count"))() :: :ok
          def unquote(String.to_atom("decrement_#{name}_count"))() do
            send_signal({{unquote(name), unquote(weight), unquote(type)}, -1.0})
          end
        end

      type ->
        quote do
          #
          #
          @spec unquote(String.to_atom("#{type}_#{name}"))(data :: any()) :: :ok
          def unquote(String.to_atom("#{type}_#{name}"))(data) do
            send_signal({{unquote(name), unquote(weight), unquote(type)}, data})
          end
        end
    end
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # callbacks for agents functions
  #

  #
  #
  @doc """
  **DO NOT USE THIS DIRECTLY.  Please utilize the `signal()` macro within the `Beethoven.Allocator.Agent` module.**

  Sends a signal message to `Allocator.Ingress`.

  # Payload schema

      {header :: {name :: atom(), weight :: integer(), type :: atom()}, payload :: signal_payload()}
  """
  @spec send_signal(signal_message()) :: :ok
  def send_signal(signal) do
    GenServer.cast(Allocator.Ingress, {:signal, signal})
  end

  #
  #
end
