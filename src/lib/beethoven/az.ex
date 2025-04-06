defmodule Beethoven.Az do
  @moduledoc """
  Azure Platform awareness for the node.
  If the app is not in Azure, genserver will response `:no_azure` to all calls.
  """

  use GenServer
  require Logger
  alias __MODULE__.Lib

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
    # Call IMDS to get initial state
    state =
      Lib.call_IMDS()
      |> case do
        # state is now deserialized response body from IMDS
        {:ok, state} ->
          region =
            state
            |> Lib.get_AzRegion()

          Logger.info("Node operating in Azure region (#{region}).")

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
  def handle_call(:get_all, _from, state) do
    {:reply, state, state}
  end

  #
  #
  # Provides networking info to caller
  @impl true
  def handle_call(:az_net, _from, state) do
    {:reply, Lib.get_AzSubnet(state), state}
  end

  #
  #
  # Provides region atom to caller
  @impl true
  def handle_call(:az_region, _from, state) do
    {:reply, Lib.get_AzRegion(state), state}
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
  \n**RETURNS ONLY PRIMARY INT FOR VM**
  """
  @spec get_AzSubnet() :: {{integer(), integer(), integer(), integer()}, integer()} | :no_azure
  def get_AzSubnet() do
    GenServer.call(__MODULE__, :az_net)
  end

  #
  #
  @doc """
  Retrieves the Azure region from IMDS data.
  """
  @spec get_AzRegion() :: atom() | :no_azure
  def get_AzRegion() do
    GenServer.call(__MODULE__, :az_region)
  end

  #
  #
  #
end
