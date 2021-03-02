defmodule Packmatic.Field.Helpers do
  @moduledoc false

  defguard fits_u8(value) when is_integer(value) and value < 256
  defguard fits_u16(value) when is_integer(value) and value < 65_536
  defguard fits_u32(value) when is_integer(value) and value < 4_294_967_296
  defguard fits_u64(value) when is_integer(value) and value < 18_446_744_073_709_551_616

  def encode_8(value) when fits_u8(value), do: <<value::size(8)-little>>
  def encode_8(_), do: <<0xFF>>

  def encode_16(value) when fits_u16(value), do: <<value::size(16)-little>>
  def encode_16(_), do: <<0xFF, 0xFF>>

  def encode_32(value) when fits_u32(value), do: <<value::size(32)-little>>
  def encode_32(_), do: <<0xFF, 0xFF, 0xFF, 0xFF>>

  def encode_64(value) when fits_u64(value), do: <<value::size(64)-little>>
  def encode_64(_), do: <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>
end
