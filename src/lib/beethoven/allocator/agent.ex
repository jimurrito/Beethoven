defmodule Beethoven.Allocator.Agent do
  @moduledoc """
  Behaviour to create an agent for data ingress into `Beethoven.Allocator`.
  """

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  # UNIQUE TYPES
  #

  #
  @typedoc """
  Defines types of signal.
  """
  @type signal_type() :: :count | :percent

  #
  @typedoc """
  Defines a single signal that this agent can accept.
  """
  @type signal() :: [name: atom(), weight: float(), type: signal_type()]

  #
  @typedoc """
  List of signals.
  """
  @type signals() :: [signal()]

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # use macro
  #

  defmacro __using__(_opts) do
    quote do
      #
      import Beethoven.Allocator.Agent
      #import Beethoven.Allocator.Tracker
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
  @spec signal(signal :: signal()) :: tuple()
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
            Beethoven.Allocator.Ingress.send_signal(
              {{unquote(name), unquote(weight), unquote(type)}, 1}
            )
          end

          #
          #
          @spec unquote(String.to_atom("decrement_#{name}_count"))() :: :ok
          def unquote(String.to_atom("decrement_#{name}_count"))() do
            Beethoven.Allocator.Ingress.send_signal(
              {{unquote(name), unquote(weight), unquote(type)}, -1}
            )
          end
        end

      type ->
        quote do
          #
          #
          @spec unquote(String.to_atom("#{type}_#{name}"))(data :: any()) :: :ok
          def unquote(String.to_atom("#{type}_#{name}"))(data) do
            Beethoven.Allocator.Ingress.send_signal(
              {{unquote(name), unquote(weight), unquote(type)}, data}
            )
          end
        end
    end
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Other
  #

  #
  #

  #
  #
end
