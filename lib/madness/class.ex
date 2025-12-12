defmodule Madness.Class do
  @moduledoc """
  DNS Resource Record Class conversions.
  """

  @type t() :: :in | :any | non_neg_integer()

  @doc """
  Convert an rrclass atom to its integer value.
  """
  @spec to_int(t()) :: non_neg_integer()
  def to_int(:in), do: 1
  def to_int(:any), do: 255
  def to_int(n) when is_integer(n), do: n

  @doc """
  Convert an integer to its rrclass atom.
  """
  @spec from_int(non_neg_integer()) :: t()
  def from_int(1), do: :in
  def from_int(255), do: :any
  def from_int(n) when is_integer(n), do: n
end
