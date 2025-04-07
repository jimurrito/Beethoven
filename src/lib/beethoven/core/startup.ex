defmodule Beethoven.Core.Startup do
  @moduledoc """
  Library for service startup. Handles Seeking of other nodes.
  """

  require Logger
  alias Beethoven.Tracker
  alias Beethoven.Utils
  alias Beethoven.Ipv4
  alias Beethoven.Core.Locator
  alias Beethoven.Az

  #
  #
  #
  @doc """
  Starts seeking for other nodes within the current node's network
  """
  @spec start_seeking(:no_azure | atom()) ::
          :clustered | :standalone | {:failed, :cluster_join_error | :copy_error}
  def start_seeking(:no_azure) do
    # Get list of hosts in defined IP range
    hostIPs = Ipv4.get_host_network_addresses()
    # get Listener port
    port = Utils.get_app_env(:listener_port, 33000)
    # start logic
    start_seek({hostIPs, port})
  end

  #
  #
  # when in Azure
  def start_seeking(_region) do
    # Determine if we need to use the VMs networking config for seeking
    Utils.get_app_env(:use_az_net, false)
    |> case do
      # Use netw config in config
      false ->
        # redirect to non azure flow
        start_seeking(:no_azure)

      # use Az VM Netw config
      true ->
        # Get network info from IMDS cache genserver
        {network, netmask} = Az.get_AzSubnet()
        # Get list of hosts in defined IP range
        hostIPs = Ipv4.get_host_network_addresses(network, netmask)
        # Due to how Azure works, will remove the first 3 addresses in the list.
        hostIPs = hostIPs |> Enum.take(-(length(hostIPs) - 3))
        # get Listener port -> used to connect to a server
        port = Utils.get_app_env(:listener_port, 33000)
        # start logic
        start_seek({hostIPs, port})
    end
  end

  #
  #
  #
  # private fun to handle logic of seeking.
  @spec start_seek({list(), integer()}, integer()) ::
          :clustered | :standalone | {:failed, :cluster_join_error | :copy_error}
  defp start_seek({hostIPs, port}, attemptNum \\ 1) do
    Logger.info("[start_seek] Starting Seek attempt (#{attemptNum |> Integer.to_string()}).")

    # attempt join on all nodes in list
    # stops at first response from a socket
    Locator.try_join_iter(hostIPs, port)
    |> case do
      # successfully joined Mnesia cluster => Cluster state
      # Tracker was either copied or already imported
      :ok ->
        Logger.info("[start_seek] Seeking completed successfully.")
        :clustered

      #
      # Got copy error from tracker table
      :copy_error ->
        Logger.emergency(
          "[start_seek] Tracker table failed to be copied into memory. Check Server logs."
        )

        {:failed, :copy_error}

      #
      # connected, but failed to join => Failed state
      :cluster_join_error ->
        Logger.emergency("[start_seek] Failed to join Mnesia Cluster. Check Server logs.")
        {:failed, :cluster_join_error}

      #
      # No sockets listening in network => retry(x3) => Standalone
      :none_found ->
        Logger.info(
          "[start_seek] No sockets found on attempt (#{attemptNum |> Integer.to_string()})."
        )

        # If attempt is #3 fallback to standalone
        if attemptNum == 3 do
          # Standalone mode
          Logger.info("[start_seek] No nodes found. Defaulting to ':standalone' mode.")

          # start Tracker
          m_result = Tracker.start()
          Logger.debug("Attempted to start Tracker.", result: m_result)
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
