defmodule Beethoven.Core.Listener.Lib do
  @moduledoc false

  require Logger
  alias Beethoven.Core.Client, as: CoreClient

  #
  #
  #
  # Fnc that runs in each request task.
  # handles logic for the client request and handles response.
  def serve(client_socket) do
    #
    Logger.info("Beethoven.Core.Listener received a connection.")
    #
    # Read data in socket
    {:ok, payload} = :gen_tcp.recv(client_socket, 0)

    nodeName =
      payload
      # Remove \r\n from the payload (if present)
      |> String.replace("\r", "")
      |> String.replace("\n", "")
      # Convert to atom
      |> String.to_atom()

    Logger.debug("Node (#{nodeName}) has requested to join the Beethoven Cluster.")
    # test connection to client
    # Target node will only respond if the name is routable and nodes share the same cookie.
    response =
      case Node.ping(nodeName) do
        #
        # Failed to connect to node
        :pang ->
          Logger.alert("Failed to ping node (#{nodeName}). Caller will not join the cluster.")
          "connection_failed"

        #
        # Success -> connected to node
        :pong ->
          # Add host to Mnesia
          add_to_mnesia(nodeName)
      end

    # Send response to caller
    :gen_tcp.send(client_socket, response)
  end

  #
  #
  #
  @doc """
  Adds target node to the Mnesia cluster.
  This allows them to interact with the tables within the cluster.

  Response is a binary instead of atom so it can be piped into the TCP response more efficiently.
  Options: "connected" | "merge_schema_failed" | "unexpected_error"
  """
  @spec add_to_mnesia(node()) :: binary()
  def add_to_mnesia(nodeName) do
    # add requester to Mnesia cluster
    :mnesia.change_config(:extra_db_nodes, [nodeName])
    |> case do
      #
      # Joined successfully.
      {:ok, _} ->
        Logger.info("Node (#{nodeName}) joined the Mnesia Cluster.")
        # Call local Core server to ensure it is in ':clustered' mode now
        _ = CoreClient.to_clustered()
        "connected"

      #
      # Failed to join - merge_schema_failed
      {:error, {:merge_schema_failed, msg}} ->
        Logger.emergency(
          "Node (#{nodeName}) failed to join Beethoven cluster 'merge_schema_failed': '#{msg}' "
        )

        "merge_schema_failed"

      #
      # Failed - unexpected_error
      {:error, error} ->
        Logger.alert(
          "Node (#{nodeName}) failed to join Beethoven cluster.",
          unexpected_error: error
        )

        "unexpected_error"
    end
  end
end
