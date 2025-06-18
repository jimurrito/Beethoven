defmodule Beethoven.Az do
  @moduledoc """

  # WORK IN PROGRESS!

  Azure Platform awareness for the node.
  If the app is not in Azure, genserver will response `:no_azure` to all calls.

  # Functions
  - `get_state/0` Returns the entire state of the GenServer.
  - `get_az_subnet/0` Returns the subnet this VM resides in. Pulls data from cache.
  - `get_az_region/0` Returns the region this VM resides in. Pulls data from cache.

  """

  use GenServer
  require Logger

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # GenServer callback functions
  #

  #
  #
  #
  @doc """
  Entry point for Supervisors. Links calling PID this this child pid.
  """
  @spec start_link(any()) :: {:ok, pid()}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  #
  #
  @impl true
  def init(_arg) do
    # ensure :inets is enabled
    _ = :inets.start()
    #
    # Call IMDS to get initial state
    state =
      call_IMDS()
      |> case do
        # state is now deserialized response body from IMDS
        {:ok, state} ->
          region =
            state
            |> get_az_region()

          Logger.info("Node operating in Azure region (#{region}).")
          state

        # Not in azure
        {:error, :timeout} ->
          Logger.info("Node is not operating in Azure.")
          :no_azure
      end

    #
    {:ok, state}
  end

  #
  #
  # Catch all calls when not in Azure
  @impl true
  def handle_call(_msg, _from, :no_azure) do
    {:reply, :no_azure, :no_azure}
  end

  #
  #
  # Dumps state to caller
  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  #
  #
  # Provides networking info to caller
  @impl true
  def handle_call(:az_net, _from, state) do
    {:reply, get_az_subnet(state), state}
  end

  #
  #
  # Provides region atom to caller
  @impl true
  def handle_call(:az_region, _from, state) do
    {:reply, get_az_region(state), state}
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Client fun(s)
  # used to access the genserver as an external caller

  #
  #
  @doc """
  Retrieves the Azure region from IMDS data.
  """
  @spec get_state() :: map() | :no_azure
  def get_state() do
    GenServer.call(__MODULE__, :get_state)
  end

  #
  #
  @doc """
  Retrieves the VM's networking config from IMDS data.
  \n**RETURNS ONLY PRIMARY INTERFACE FOR VM**
  """
  @spec get_az_subnet() :: {{integer(), integer(), integer(), integer()}, integer()} | :no_azure
  def get_az_subnet() do
    GenServer.call(__MODULE__, :az_net)
  end

  #
  #
  @doc """
  Retrieves the Azure region from IMDS data.
  """
  @spec get_az_region() :: atom() | :no_azure
  def get_az_region() do
    GenServer.call(__MODULE__, :az_region)
  end

  #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  # Internal functions
  #

  #
  #
  #
  # Gets the VM's networking config from cached IMDS data.
  @spec get_az_subnet(map()) ::
          {{integer(), integer(), integer(), integer()}, integer()}
  defp get_az_subnet(metadata) do
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
  # Gets the VM's Azure region from cached IMDS data.
  @spec get_az_region(map()) :: atom()
  defp get_az_region(metadata) do
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
  #
  # Calls IMDS to get metadata about this VM.
  # A response of `{:error, :timeout}` indicates that you are not in Azure.
  # IMDS should never go down or be unreachable outside of a live-site outage.
  @spec call_IMDS() :: {:ok, map()} | {:error, :timeout}
  defp call_IMDS() do
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

  #
  #
  #
end
