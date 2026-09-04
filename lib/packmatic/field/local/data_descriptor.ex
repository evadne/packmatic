defmodule Packmatic.Field.Local.DataDescriptor do
  @moduledoc """
  Represents the Data Descriptor, which is used to facilitate streaming. This is requried since
  Packmatic assembles the files on the fly, so it does not know the size until the entire source
  has been read.

  ## Structure

  ### Data Descriptor

  Size     | Content
  -------- | -
  4 bytes  | Signature
  4 bytes  | Checksum (CRC-32)
  4/8 bytes | Compressed Size (Bytes)
  4/8 bytes | Original Size (Bytes)

  #### Notes

  1.  APPNOTE section 4.3.9 recommends 8-byte sizes when an entry exceeds the Zip32 limit and
      permits them regardless of size. Packmatic uses 8-byte sizes only when required, retaining
      compatibility with single-pass streaming decoders that select the descriptor width from the
      number of bytes processed.
  """

  @type t :: %__MODULE__{
          checksum: non_neg_integer(),
          size_compressed: non_neg_integer(),
          size: non_neg_integer()
        }

  @enforce_keys ~w(checksum size_compressed size)a
  defstruct checksum: nil, size_compressed: nil, size: nil
end

defimpl Packmatic.Field, for: Packmatic.Field.Local.DataDescriptor do
  import Packmatic.Field.Helpers

  def encode(target) do
    [
      <<0x50, 0x4B, 0x07, 0x08>>,
      encode_32(target.checksum),
      encode_sizes(target)
    ]
  end

  defp encode_sizes(target)
       when fits_u32(target.size_compressed) and fits_u32(target.size) do
    [encode_32(target.size_compressed), encode_32(target.size)]
  end

  defp encode_sizes(target) do
    [encode_64(target.size_compressed), encode_64(target.size)]
  end
end
