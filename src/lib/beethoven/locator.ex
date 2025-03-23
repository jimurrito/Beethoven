defmodule Beethoven.Locator do
  @moduledoc """
  Module for finding a Beethoven listener.
  """

  require Logger

  alias Beethoven.Tracker

  @doc """
  Attempts join to a Beethoven Listener Socket server hosted on another Elixir node.
  Using the provided socket info, the client will attempt to connect to the socket and deliver its node uri as a payload.
  """
  @spec try_join({integer(), integer(), integer(), integer()}, integer()) ::
          :ok | :cluster_join_error | :copy_error | :coord_listener_conn_error
  def try_join(ipAddr, port) do
    # Convert ipaddress tuple to string for logging
    ipString = :inet.ntoa(ipAddr)
    Logger.info("Attempting connection to Beethoven Listener @ '#{ipString}'.")
    # attempt connection to listener (250 milisecond timeout)
    case :gen_tcp.connect(ipAddr, port, [:binary, packet: 0, active: false], 250) do
      # Connected to listener
      {:ok, server_socket} ->
        Logger.info("Successfully connected to Beethoven Listener socket  @ '#{ipString}'.")
        Logger.debug("Sending node URI '#{node()}' to the listener socket.")
        :ok = :gen_tcp.send(server_socket, Atom.to_string(node()))

        # get payload response from server
        {:ok, payload} = :gen_tcp.recv(server_socket, 0)

        # Close socket
        :gen_tcp.close(server_socket)

        payload
        # Convert response to Atom
        |> String.to_atom()
        |> case do
          # Joined Cluster
          :joined ->
            Logger.info("Successfully joined to Mnesia cluster.")
            # Add self to BeethovenTracker
            Tracker.join()
            |> case do
              # Successfully added self
              :ok ->
                :ok

              :not_started ->
                # failed
                Logger.error(
                  "Failed to write self to 'BeethovenTracker' table. [:not_started] Going into failed state."
                )

                :cluster_join_error

              :copy_error ->
                # failed
                Logger.error(
                  "Failed to copy'BeethovenTracker' table to memory. Going into failed state."
                )

                :copy_error
            end

          _error ->
            Logger.error("Failed to join Mnesia cluster: ':cluster_join_error'")

            :cluster_join_error
        end

      # Failed to connect for some reason.
      _error ->
        Logger.warning("Failed connection attempt to '#{ipString}': ':coord_listener_conn_error'")
        :coord_listener_conn_error
    end
  end

  @doc """
  Iterates through a list of IPs and tries to find one running a Beethoven Listener.
  Same returns as `try_join/2`.
  """
  @spec try_join_iter([{integer(), integer(), integer(), integer()}], integer()) ::
          :ok | :cluster_join_error | :copy_error | :none_found
  def try_join_iter(ipList, port) do
    Logger.info(
      "Begin cluster join iteration. (#{length(ipList)}) node IP(s) to attempt join with."
    )

    try_join_iter(ipList, port, 1)
  end

  # out of nodes
  defp try_join_iter([], _port, _acc) do
    :none_found
  end

  # working loop
  defp try_join_iter([hostIP | ipList], port, acc) do
    try_join(hostIP, port)
    |> case do
      # Joined from IP used
      :ok ->
        Logger.debug("Successfully joined cluster after (#{acc}) attempt(s).")
        :ok

      # Failed to join cluster
      :copy_error ->
        Logger.debug("Table copy failure occurred on attempt #(#{acc}).")
        :copy_error

      # Failed to join cluster
      :cluster_join_error ->
        Logger.debug("Join failure occurred on attempt #(#{acc}).")
        :cluster_join_error

      # Unable to connect to socket (if any)
      :coord_listener_conn_error ->
        Logger.debug(
          "Connection attempt #(#{acc}) failed to connect to a socket @ '#{:inet.ntoa(hostIP)}'"
        )

        # try next IP
        try_join_iter(ipList, port, acc + 1)
    end
  end
end
