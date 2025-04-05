defmodule Beethoven.Ipv4 do
  @moduledoc """
  Module to handle scanning IPV4 addresses within a network.
  """

  require Logger
  alias :inet, as: IP

  #
  #
  #
  @doc """
  Retrieves the hosts IP address. Pulls Network and Netmask from the config.
  """
  @spec get_host_network_addresses() :: list()
  def get_host_network_addresses() do
    # Get Cluster network from config
    clusterNet =
      Application.fetch_env(:beethoven, :cluster_net)
      |> case do
        {:ok, value} ->
          value

        :error ->
          Logger.notice(":cluster_net not set in config/*.exs. Using default value '127.0.0.1'.")
          "127.0.0.0"
      end

    clusterNetMask =
      Application.fetch_env(:beethoven, :cluster_net_mask)
      |> case do
        {:ok, value} ->
          value

        :error ->
          Logger.notice(":cluster_net_mask not set in config/*.exs. Using default value '29'.")
          "29"
      end

    # Convert to IP Type
    {:ok, clusterNetParse} = IP.parse_address(~c"#{clusterNet}")
    # get all IPs in the network
    get_hosts(clusterNetParse, clusterNetMask)
  end

  #
  #
  #

  @doc """
  Same as get_host_network_addresses/0 but works off provided network and netmask.
  """
  @spec get_host_network_addresses({integer(), integer(), integer(), integer()}, integer()) ::
          list()
  def get_host_network_addresses(clusterNet, clusterNetMask) do
    get_hosts(clusterNet, clusterNetMask)
  end

  #
  #
  #
  @doc """
  Gets the number of IPs within a netmask.
  """
  @spec get_netmask_hosts(binary() | integer()) :: integer()
  def get_netmask_hosts(mask) when is_binary(mask) do
    get_netmask_hosts(String.to_integer(mask))
  end

  def get_netmask_hosts(mask) when is_integer(mask) do
    :math.pow(2, 32 - mask) - 2
  end

  #
  #
  #
  @doc """
  Generates a list of hosts with the network and netmask provided
  """
  @spec get_hosts({integer(), integer(), integer(), integer()}, integer()) :: list()
  def get_hosts(address, mask) do
    # gets number of hosts within the network
    numOfHosts = get_netmask_hosts(mask)
    #
    get_hosts(address, numOfHosts, [], 0)
  end

  # End loop
  defp get_hosts(_address, numOfHosts, state, acc) when numOfHosts == acc do
    state |> Enum.reverse()
  end

  # working loop
  defp get_hosts(address, numOfHosts, state, acc) do
    address = increment_ip(address)
    get_hosts(address, numOfHosts, [address | state], acc + 1)
  end

  #
  #
  #
  @doc """
  Increments IP by one host.
  """
  @spec increment_ip({integer(), integer(), integer(), integer()}) ::
          {integer(), integer(), integer(), integer()}
  def increment_ip({255, 255, 255, 255}) do
    raise "Next IP address is not valid! 'input_ip: {254, 254, 254, 254}'"
  end

  def increment_ip({oct1, 255, 255, 255}) do
    {oct1 + 1, 0, 0, 0}
  end

  def increment_ip({oct1, oct2, 255, 255}) do
    {oct1, oct2 + 1, 0, 0}
  end

  def increment_ip({oct1, oct2, oct3, 255}) do
    {oct1, oct2, oct3 + 1, 0}
  end

  def increment_ip({oct1, oct2, oct3, oct4}) do
    {oct1, oct2, oct3, oct4 + 1}
  end
end
