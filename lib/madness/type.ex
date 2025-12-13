defmodule Madness.Type do
  @moduledoc """
  DNS Resource Record Type conversions.
  """

  defguard is_valid_type(t)
           when t in [:a, :ns, :cname, :ptr, :txt, :aaaa, :srv, :nsec, :any] or is_integer(t)

  @type t() :: non_neg_integer() | atom()

  @type query_type() :: :a | :cname | :ptr | :txt | :aaaa | :srv | :any

  defguard is_valid_query_type(t)
           when t in [:a, :cname, :ptr, :txt, :aaaa, :srv, :any]

  @doc """
  Convert an rrtype atom to its integer value.
  """
  @spec to_int(t()) :: non_neg_integer()
  def to_int(:a), do: 1
  def to_int(:ns), do: 2
  def to_int(:cname), do: 5
  def to_int(:ptr), do: 12
  def to_int(:txt), do: 16
  def to_int(:aaaa), do: 28
  def to_int(:srv), do: 33
  def to_int(:nsec), do: 47
  def to_int(:any), do: 255
  def to_int(n) when is_integer(n), do: n

  @doc """
  Convert an integer to its rrtype atom.
  """
  @spec from_int(non_neg_integer()) :: t()
  def from_int(1), do: :a
  def from_int(2), do: :ns
  def from_int(5), do: :cname
  def from_int(12), do: :ptr
  def from_int(16), do: :txt
  def from_int(28), do: :aaaa
  def from_int(33), do: :srv
  def from_int(47), do: :nsec
  def from_int(255), do: :any
  def from_int(n) when is_integer(n), do: n
end
