defmodule Madness do
  @moduledoc """
  Documentation for `Madness`.
  """

  use TypedStruct

  alias Madness.Message
  alias Madness.Question
  alias Madness.Type

  import Type, only: [is_valid_query_type: 1]

  @mdns_port 5353
  @mdns_ipv4 {224, 0, 0, 251}

  typedrecord :query, visibility: :opaque do
    field :port, non_neg_integer(), default: 0
    field :questions, [Madness.Question.t()], default: []
  end

  @spec new_query() :: query()
  def new_query, do: query()

  @spec new_query(String.t(), Type.query_type()) :: query()
  @spec new_query(String.t(), Type.query_type(), boolean()) :: query()
  def new_query(name, type, unicast_response \\ true) do
    new_query() |> add_qstn(name, type, unicast_response)
  end

  @spec add_qstn(query(), String.t(), Type.query_type()) :: query()
  @spec add_qstn(query(), String.t(), Type.query_type(), boolean()) :: query()
  def add_qstn(query() = q, name, type, unicast_response \\ true)
      when is_binary(name) and is_valid_query_type(type) and is_boolean(unicast_response) do
    # If the unicast_response is false, at least one question wants a multicast response
    # so we set the port to 5353 (the mDNS port)
    qry = if unicast_response, do: q, else: query(q, port: @mdns_port)

    question = Question.new(%{name: name, type: type, unicast_response: unicast_response})
    questions = [question | query(qry, :questions)]
    query(qry, questions: questions)
  end

  @spec stream(query()) :: Enumerable.t()
  @spec stream(query(), keyword()) :: Enumerable.t()
  def stream(query, opts \\ [])

  def stream(query(questions: []), _opts), do: []

  def stream(query() = q, opts) do
    Stream.resource(fn -> send_query(q, opts) end, &recv_responses/1, &close/1)
  end

  defp send_query(query(port: 0) = q, opts) do
    {:ok, sock} = :gen_udp.open(0, [:binary, active: :once])
    msg = Message.encode_query(query(q, :questions))
    :ok = :gen_udp.send(sock, @mdns_ipv4, @mdns_port, msg)
    tmo = Keyword.get(opts, :timeout, 5000)
    Process.send_after(self(), {:timeout, sock}, tmo)
    sock
  end

  defp recv_responses(sock) do
    receive do
      {:udp, ^sock, _ip, _port, data} ->
        responses = decode_responses(data)
        :ok = :inet.setopts(sock, active: :once)
        {responses, sock}

      {:timeout, ^sock} ->
        receive do
          {:udp, ^sock, _ip, _port, _} ->
            :ok
        after
          0 ->
            :ok
        end

        {:halt, sock}
    end
  end

  defp close(sock) do
    :gen_udp.close(sock)
  end

  defp decode_responses(data), do: decode_responses(data, [])
  defp decode_responses(<<>>, acc), do: Enum.reverse(acc)

  defp decode_responses(data, acc) do
    {:ok, msg, rest} = Message.decode(data)
    decode_responses(rest, [msg | acc])
  end
end
