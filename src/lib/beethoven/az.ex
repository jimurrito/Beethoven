defmodule Beethoven.Az do
  @moduledoc """
  Azure Platform awareness for the cluster. If not in Azure, a local environment global group will be used.
  """

  require Logger

  #
  #
  @doc """
  ONLY WORKS IN AZURE.

  Calls IMDS to get the subnet and netmask of the current VM.
  """
  @spec get_AzSubnet() ::
          {:ok, {integer(), integer(), integer(), integer()}, integer()} | :no_azure
  def get_AzSubnet() do
    call_IMDS()
    |> case do
      {:ok, metadata} ->
        network_config =
          metadata
          |> Map.fetch!("network")
          |> Map.fetch!("interface")
          # gets first interface
          |> List.first()
          # get only IPV4
          |> Map.fetch!("ipv4")
          |> Map.fetch!("subnet")
          |> List.first()

        # Get ip address network
        ip_address =
          network_config
          |> Map.fetch!("address")
          # deserialize Ipaddress string into 4 elem tuple
          |> :inet.ntoa()

        # Netmask
        netmask =
          network_config
          |> Map.fetch!("prefix")
          |> String.to_integer()

        # return
        {:ok, ip_address, netmask}

      {:error, :timeout} ->
        :no_azure
    end
  end

  #
  #
  @doc """
  ONLY WORKS IN AZURE.

  Calls IMDS to get the region this machine is in.
  """
  @spec get_AzRegion() :: binary() | :no_azure
  def get_AzRegion() do
    call_IMDS()
    |> case do
      {:ok, metadata} ->
        metadata
        |> Map.fetch!("compute")
        |> Map.fetch!("location")

      {:error, :timeout} ->
        :no_azure
    end
  end

  #
  #
  @doc """
  ONLY WORKS IN AZURE.

  Calls IMDS to get metadata about this VM. A response of `{:error, :timeout}` indicates that you are not in Azure. IMDS should never go down.
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
        Logger.debug("Got response from IMDS.")
        resp_body = body |> elem(2) |> to_string() |> :json.decode()
        {:ok, resp_body}

      # Timeout - not in Azure or IMDS is down (LOL)
      {:error, :timeout} ->
        Logger.warning("No response from IMDS. Assuming on-prem deployment.")
        {:error, :timeout}
    end
  end
end
