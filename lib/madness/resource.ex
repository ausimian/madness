defmodule Madness.Resource do
  @moduledoc """
  DNS Resource Record representation and encoding/decoding.
  """

  use TypedStruct
  import Bitwise

  @typedoc "IPv4 address"
  @type a() :: :socket.in_addr()
  @typedoc "IPv6 address"
  @type aaaa() :: :socket.in6_addr()
  @typedoc "Canonical name"
  @type cname() :: String.t()
  @typedoc "Pointer record"
  @type ptr() :: String.t()
  @typedoc "Service record"
  @type srv() :: %{
          priority: non_neg_integer(),
          weight: non_neg_integer(),
          port: non_neg_integer(),
          target: String.t()
        }
  @typedoc "Text record"
  @type txt() :: [String.t()]

  @typedoc """
  DNS Resource Record data types.
  """
  @type rdata() ::
          a()
          | aaaa()
          | cname()
          | ptr()
          | srv()
          | txt()
          | binary()

  typedstruct enforce: true do
    field(:name, String.t())
    field(:type, Madness.Type.t())
    field(:class, Madness.Class.t(), default: :in)
    field(:cache_flush, boolean(), default: false)
    field(:ttl, non_neg_integer())
    field(:rdata, rdata())
  end

  @type params() :: %{
          required(:name) => String.t(),
          required(:type) => Madness.Type.t(),
          required(:rdata) => rdata(),
          required(:ttl) => non_neg_integer(),
          optional(:class) => Madness.Class.t(),
          optional(:cache_flush) => boolean()
        }

  @doc """
  Create a new `%Madness.Resource{}` struct.

  ## Parameters
    - attrs: A map of attributes to create the resource with.

  ## Returns
    - A new `%Madness.Resource{}` struct.
  """
  @spec new(params()) :: t()
  def new(attrs) do
    attrs
    |> Map.put_new(:class, :in)
    |> Map.put_new(:cache_flush, false)
    |> then(&struct(__MODULE__, &1))
  end

  @doc """
  Encode a DNS Resource Record.

  Encodes the resource record into its binary representation, handling name compression
  and RDATA encoding based on the record type.

  ## Parameters

    - resource: The `%Madness.Resource{}` struct to encode.
    - suffix_map: A map used for name compression (default: empty map).
    - base_offset: The current offset in the DNS message for compression (default: 0).

  ## Returns
    - A tuple `{encoded_binary, updated_suffix_map}` where `encoded_binary` is the
      binary representation of the resource record and `updated_suffix_map` is the
      suffix map after encoding.
  """
  @spec encode(t(), map(), non_neg_integer()) :: {binary(), map()}
  def encode(%__MODULE__{} = resource, suffix_map \\ %{}, base_offset \\ 0) do
    {encoded_name, updated_suffix_map} =
      Madness.Name.encode(resource.name, suffix_map, base_offset)

    type_value = Madness.Type.to_int(resource.type)
    class_value = Madness.Class.to_int(resource.class)
    cache_flush_bit = if resource.cache_flush, do: 0x8000, else: 0x0000

    {rdata, updated_suffix_map} =
      Madness.Rdata.encode(
        resource.type,
        resource.rdata,
        updated_suffix_map,
        base_offset + byte_size(encoded_name) + 10
      )

    rdlength = byte_size(rdata)

    encoded_resource =
      <<
        encoded_name::binary,
        type_value::16,
        class_value ||| cache_flush_bit::16,
        resource.ttl::32,
        rdlength::16,
        rdata::binary
      >>

    {encoded_resource, updated_suffix_map}
  end

  @spec decode(binary(), binary() | nil) :: {:ok, t()} | {:error, String.t()}
  def decode(data, original_message \\ nil) do
    with {:ok, name, rest} <- Madness.Name.decode(data, original_message) do
      case rest do
        <<type::16, class::16, ttl::32, rdlength::16, rdata_binary::binary-size(rdlength),
          rest2::binary>> ->
          cache_flush = (class &&& 0x8000) != 0
          actual_class = class &&& 0x7FFF
          record_type = Madness.Type.from_int(type)

          rdata = Madness.Rdata.decode(record_type, rdata_binary, original_message || data)

          resource = %__MODULE__{
            name: name,
            type: record_type,
            class: Madness.Class.from_int(actual_class),
            cache_flush: cache_flush,
            ttl: ttl,
            rdata: rdata
          }

          {:ok, resource, rest2}

        _ ->
          {:error, "insufficient data to decode resource record"}
      end
    end
  end
end
