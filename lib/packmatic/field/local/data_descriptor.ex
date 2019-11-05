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
  4 bytes  | Compressed Size (Bytes)
  4 bytes  | Original Size (Bytes)

  #### Notes

  1.  Although the APPNOTE indicates that Zip64 format should be used, 8-byte sizes crash the
      Unarchiver process on macOS High Sierra, but a truncated one works totally fine.
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
      encode_32(target.size_compressed),
      encode_32(target.size)
    ]
  end
end
