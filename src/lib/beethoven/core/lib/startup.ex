defmodule Beethoven.Core.Lib.Startup do
  @moduledoc """
  Library for service startup. Handles Seeking of other nodes.
  """

  require Logger
  alias Beethoven.Utils
  alias Beethoven.Ipv4
  alias Beethoven.Locator
  alias Beethoven.Az

  #
  #
  #
  @doc """
  Starts seeking for other nodes within the current node's network
  """
  @spec start_seeking(:no_azure | atom()) ::
          :clustered | :standalone | {:failed, :cluster_join_error}
  def start_seeking(:no_azure) do
    hostIPs = Ipv4.get_host_network_addresses()
    # get Listener port
    port =
      Application.fetch_env(:beethoven, :listener_port)
      |> case do
        {:ok, value} ->
          value

        :error ->
          Logger.notice(":listener_port is not set in config/*.exs. defaulting to (33000).")
          33000
      end

    # start logic
    start_seek({hostIPs, port})
  end

  #
  #
  # when in Azure
  def start_seeking(_region) do
    # Get network info from IMDS
    {:ok, network, netmask} = Az.get_AzSubnet()
    hostIPs = Ipv4.get_host_network_addresses(network, netmask)
    # Due to how Azure works, will remove the first 3 addresses in the list.
    hostIPs = hostIPs |> Enum.take(-(length(hostIPs) - 3))
    # get Listener port -> used to connect to a server
    port =
      Application.fetch_env(:beethoven, :listener_port)
      |> case do
        {:ok, value} ->
          value

        :error ->
          Logger.notice(":listener_port is not set in config/*.exs. defaulting to (33000).")
          33000
      end

    # start logic
    start_seek({hostIPs, port})
  end

  #
  # private fun to handle logic of seeking.
  @spec start_seek({list(), integer()}, integer()) ::
          :clustered | :seeking | :standalone | {:failed, :cluster_join_error}
  defp start_seek({hostIPs, port}, attemptNum \\ 1) do
    Logger.info("[start_seek] Starting Seek attempt (#{attemptNum |> Integer.to_string()}).")

    # attempt join on all nodes in list
    # stops at first response from a socket
    Locator.try_join_iter(hostIPs, port)
    |> case do
      # successfully joined Mnesia cluster => Cluster state => need to make ram copies
      :ok ->
        Logger.info("[start_seek] Seeking completed successfully.")
        :clustered

      # Got copy error from tracker table
      # Will attempt to continue forward
      :copy_error ->
        Logger.info("[start_seek] Tracker table failed to copy or is already copied. Attempting to go ahead as is.")
        :clustered

      # connected, but failed to join => Failed state
      :cluster_join_error ->
        Logger.alert("[start_seek] Failed to join Mnesia Cluster. Check Server logs.")
        {:failed, :cluster_join_error}

      # No sockets listening in network => retry(x3) => Standalone
      :none_found ->
        Logger.info(
          "[start_seek] No sockets found on attempt (#{attemptNum |> Integer.to_string()})."
        )

        # If attempt is #3 fallback to standalone
        if attemptNum == 3 do
          # Standalone mode
          Logger.info("[start_seek] No nodes found. Defaulting to ':standalone' mode.")
          :standalone
        else
          # Retry
          # backoff in milliseconds (100-2000) milliseconds
          Utils.backoff(20, 0, 100)
          # recurse
          start_seek({hostIPs, port}, attemptNum + 1)
        end
    end
  end
end
