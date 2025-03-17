defmodule Beethoven.Utils do
  @moduledoc """
  Module for generic utilities.
  """

  require Logger

  @doc """
  Performs a backoff wait to void race conditions in a distributed environment.
  (:rand.uniform(1 - max) + delta) * multiplier
  """
  def backoff(max \\ 20, delta \\ 0, multiplier \\ 1) do
    # backoff in milliseconds
    backoff = (:rand.uniform(max) + delta) * multiplier
    Logger.debug("Backoff for (#{backoff |> Integer.to_string()}) milliseconds started.")
    Process.sleep(backoff)
  end
end
