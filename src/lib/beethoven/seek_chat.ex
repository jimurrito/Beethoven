defmodule Beethoven.SeekChat do
  @moduledoc """
  Module to simplify the interface between nodes during the locator Seeking flow.
  """

  #
  @typedoc """
  Type for sending messages between Locator and Listening Servers.
  """
  @type msg() ::
          %{sender: node(), type: type(), payload: payload()}
  #
  @typedoc """
  Request type for a node seeking message.
  # Client Options
  - `:seeking` --> Client looking to join.
  - `:watching` --> Client checking if anything else is listening.
  # Server Options
  - `:reply` --> Server response to either message
  """
  @type type() :: :seeking | :watching | :reply
  #
  @typedoc """
  Message payload.
  # Options:
  - `:join` --> (CLIENT) Seeking to join a cluster.
  - `:check` --> (CLIENT) Client is watching, and wants to know if we are in a cluster.
  - `:self` --> (SERVER) When client calls its own listener.
  - `list(node())` --> (SERVER) When client is watching, and server is in a cluster.
  - `:standalone` --> (SERVER) When client is watching, and the server is in standalone mode.
  - `:joined` --> (SERVER) Client request to join was successful.
  - `:join_failed` --> (SERVER) Client request to join failed.
  - `:error` --> (SERVER) Generic error occurred.
  """
  @type payload() ::
          :join | :check | :self | [node()] | :standalone | :joined | :join_failed | :error

  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  @doc """
  Creates a new msg, in the form of `msg()`.
  # `type()`
  - `:seeking` --> (CLIENT) Client looking to join.
  - `:watching` --> (CLIENT) Client checking if anything else is listening.
  - `:reply` --> (SERVER) Server response to either message
  ---
  # `payload()`:
  - `:join` --> (CLIENT) Seeking to join a cluster.
  - `:check` --> (CLIENT) Client is watching, and wants to know if we are in a cluster.
  - `:self` --> (SERVER) When client calls its own listener.
  - `list(node())` --> (SERVER) When client is watching, and server is in a cluster.
  - `:standalone` --> (SERVER) When client is watching, and the server is in standalone mode.
  - `:joined` --> (SERVER) Client request to join was successful.
  - `:join_failed` --> (SERVER) Client request to join failed.
  - `:error` --> (SERVER) Generic error occurred.
  """
  @spec new_msg(type(), payload()) :: msg()
  def new_msg(type, payload) do
    %{sender: node(), type: type, payload: payload}
  end

  #
  #
  #
  @doc """
  Deserializes a binary into `msg()` type.
  """
  @spec decode(binary()) :: msg()
  def decode(msg) do
    %{"sender" => sender, "type" => type, "payload" => payload} = :json.decode(msg)
    #
    # parse payload
    payload =
      if is_list(payload) do
        # If payload is a list, make list(binary()) -> list(atom()).
        Enum.map(payload, &String.to_atom(&1))
      else
        # Make an atom
        String.to_atom(payload)
      end

    # return atom map
    %{sender: String.to_atom(sender), type: String.to_atom(type), payload: payload}
  end

  #
  #
  @doc """
  Serializes a `msg()` object into a binary.
  """
  @spec encode(msg()) :: binary()
  def encode(msg) do
    msg |> :json.encode() |> to_string()
  end

  #
  #
end
