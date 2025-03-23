defmodule Beethoven.Core.Lib.Transition do
  @moduledoc """
  Library to reduce code length of Core server.
  Handles logic for mode transitions
  """

  require Logger
  alias Beethoven.Listener

  #
  #
  @spec transition(atom(), atom()) :: :ok | :noop
  def transition(mode, new_mode) do
    case new_mode do
      # is same mode
      ^mode -> :noop
      # changing modes
      :standalone -> to_standalone()
      :clustered -> to_clustered()
    end
  end

  #
  #
  # Converts service from clustered to standalone
  @spec to_standalone() :: :ok
  defp to_standalone() do
    # Ensure Listener is on
    _ = Listener.start([])
    #
    :ok
  end

  #
  #
  # Converts service from standalone to clustered
  @spec to_clustered() :: :ok
  defp to_clustered() do
    #
    :ok
  end

  #
  #
end
