defmodule Beethoven.Role do
  @moduledoc """
  Handles role re/assignment between clusters.
  """

  use GenServer
  require Logger

  alias Beethoven.Core, as: BeeServer

  # Entry point for Supervisors
  def start_link(_args) do
    GenServer.start(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    {:ok, []}
  end

end
