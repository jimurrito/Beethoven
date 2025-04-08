defmodule Beethoven.RoleAlloc.MnesiaNotify do
  @moduledoc """
  Library to simplify handling Mnesia events
  """
  require Logger
  alias Beethoven.RoleAlloc.Lib
  alias Beethoven.RoleAlloc.Client

  #
  #
  #
  @doc """
  Entry function to decide what is done when the Mnesia Event occurs.
  """
  @spec run(any(), map(), :queue.queue(node()), tuple()) :: {:ok, :queue.queue(node()), tuple()}
  def run(msg, roles, host_queue, retry_tup) do
    msg
    |> case do
      #
      # New node was added to the 'Beethoven.Tracker' table
      {:write, Beethoven.Tracker, {Beethoven.Tracker, nodeName, _, :online, _}, [], _pid_struct}
      when nodeName != node() ->
        #
        Logger.info("A new node (#{nodeName}) has joined the cluster. Starting timed assign job.")
        :ok = Client.timed_assign()
        # Add to queue
        host_queue = nodeName |> :queue.in(host_queue)
        # Reset max thresholds
        {:ok, host_queue, Lib.get_new_retries(roles)}

      #
      # Node changed from online to offline in 'Beethoven.Tracker' table
      {:write, Beethoven.Tracker, {Beethoven.Tracker, nodeName, _, :offline, _},
       [{Beethoven.Tracker, nodeName, _, :online, _}], _pid_struct} ->
        #
        Logger.info("A cluster node (#{nodeName}) has gone offline. Starting Clean-up job.")
        :ok = Client.start_cleanup()
        # remove from queue
        host_queue = nodeName |> :queue.delete(host_queue)
        # Do not reset retries as :clean_up will do it anyways
        {:ok, host_queue, retry_tup}

      #
      # Node changed from offline to online in 'Beethoven.Tracker' table
      {:write, Beethoven.Tracker, {Beethoven.Tracker, nodeName, _, :online, _},
       [{Beethoven.Tracker, nodeName, _, :offline, _}], _pid_struct}
      when nodeName != node() ->
        #
        Logger.info(
          "A cluster node (#{nodeName}) has came back online. Starting timed Assign job."
        )

        :ok = Client.timed_assign()
        # Add to queue
        host_queue = nodeName |> :queue.in(host_queue)
        # Reset max thresholds
        {:ok, host_queue, Lib.get_new_retries(roles)}

      #
      # Catch all
      _ ->
        # return queue as-is
        {:ok, host_queue, retry_tup}
        #
        #
    end
  end
end
