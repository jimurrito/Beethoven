defmodule Beethoven.Az.Lib do
  @moduledoc """
  Library for Az Genserver
  """

  require Logger

  #
  #
  #
  @doc """
  Gets the VM's networking config from cached IMDS data.
  """
  @spec get_AzSubnet(map()) ::
          {{integer(), integer(), integer(), integer()}, integer()}
  def get_AzSubnet(metadata) do
    network_config =
      metadata
      |> Map.fetch!("network")
      |> Map.fetch!("interface")
      # gets first interface
      |> List.first()
      # get only IPV4
      |> Map.fetch!("ipv4")
      |> Map.fetch!("subnet")
      # checks only the first Interface
      |> List.first()

    # Get ip address network
    ip_address =
      network_config
      |> Map.fetch!("address")
      # erlang expects strings to be charlist sometimes.
      |> to_charlist()
      # deserialize Ipaddress string into 4 elem tuple
      |> :inet.parse_address()
      # unwraps  {:ok, {172, 19, 0, 16}}
      |> elem(1)

    # Netmask
    netmask =
      network_config
      |> Map.fetch!("prefix")
      |> String.to_integer()

    # return
    {ip_address, netmask}
  end

  #
  #
  #
  @doc """
  Gets the VM's Azure region from cached IMDS data.
  """
  @spec get_AzRegion(map()) :: atom()
  def get_AzRegion(metadata) do
    metadata
    |> Map.fetch!("compute")
    |> Map.fetch!("location")
    |> String.to_atom()
  end

  #
  #
  #
  #
  #
  @doc """
  Calls IMDS to get metadata about this VM.
  A response of `{:error, :timeout}` indicates that you are not in Azure.
  IMDS should never go down or be unreachable outside of a live-site outage.
  """
  @spec call_IMDS() :: {:ok, map()} | {:error, :timeout}
  def call_IMDS() do
    # ensure :inets is enabled
    _ = :inets.start()
    # call IMDS and get metadata
    :httpc.request(
      # Method
      :get,
      {
        # URL
        "http://169.254.169.254/metadata/instance?api-version=2021-02-01",
        # Headers
        [{~c"Metadata", ~c"true"}]
      },
      # Options
      [{:timeout, 500}],
      # Profile
      []
    )
    |> case do
      # Get body of response and deserialize
      {:ok, body} ->
        # Logger.debug("Got response from IMDS.")
        resp_body = body |> elem(2) |> to_string() |> :json.decode()
        {:ok, resp_body}

      # Timeout - not in Azure or IMDS is down (LOL)
      {:error, :timeout} ->
        Logger.warning("No response from IMDS. Request for metadata has timed out!.")
        {:error, :timeout}
    end
  end
end
