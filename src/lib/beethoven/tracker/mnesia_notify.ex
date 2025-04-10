defmodule Beethoven.Tracker.MnesiaNotify do
  @moduledoc """
  Generic Module for handling Mnesia notifications from `Beethoven.Tracker`.
  """

  @doc """
  Handles the update events from `Beethoven.Tracker`, and returns a tuple or atom depending on the message contents.
  """
  @spec handle(tuple()) :: {:new | :offline | :online, node()} | :noop
  def handle(msg) do
    msg
    |> case do
      #
      # New node was added to the 'Beethoven.Tracker' table
      {:write, Beethoven.Tracker, {Beethoven.Tracker, nodeName, _, :online, _}, [], _pid_struct}
      when nodeName != node() ->
        {:new, nodeName}

      #
      # Node changed from online to offline in 'Beethoven.Tracker' table
      {:write, Beethoven.Tracker, {Beethoven.Tracker, nodeName, _, :offline, _},
       [{Beethoven.Tracker, nodeName, _, :online, _}], _pid_struct} ->
        {:offline, nodeName}

      #
      # Node changed from offline to online in 'Beethoven.Tracker' table
      {:write, Beethoven.Tracker, {Beethoven.Tracker, nodeName, _, :online, _},
       [{Beethoven.Tracker, nodeName, _, :offline, _}], _pid_struct}
      when nodeName != node() ->
        {:online, nodeName}

      #
      # ignore other changes
      _other ->
        # IO.inspect({:unmapped_mnesia_event, other})
        :noop
        #
    end
  end
end
