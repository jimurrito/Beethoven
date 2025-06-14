defmodule Beethoven.Allocator.Types do
  @moduledoc false

  #
  @typedoc """
  Defines types of signal that can be used.
  """
  @type signal_type() :: :count | :percent| :pre_processed

  #
  @typedoc """
  Defines a single signal. Commonly used as an input for the `signal()` macro.
  """
  @type signal_definition() :: [name: atom(), weight: float(), type: signal_type()]

  #
  @typedoc """
  Message wrapper for sending payload to `Beethoven.Allocator.Ingress`.
  """
  @type signal_message() ::
          {header :: signal_message_header(), payload :: float()}

  #
  @typedoc """
  Header for the signal metadata; when sending a signal to `Beethoven.Allocator.Ingress`.
  """
  @type signal_message_header() :: {name :: atom(), weight :: float(), type :: signal_type()}

  #
  #
end
