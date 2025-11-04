defmodule Packmatic.Field.Shared.ExtendedInformation do
  @moduledoc """
  Represents the Zip64 Extended Information Extra Field, which can be emitted in both Local and
  Central File Headers, but in practice only used in the Central File Header within Packmatic, due
  to its streaming nature.

  This field always emits Zip64 representations of the 3 relevant fields (Original Size, Compressed
  Size, or Offset), whether they could or could not fit within 4 bytes; their respective Zip32
  representations were always filled with 0xFF. This is based on the relevant section of the
  APPNOTE:

  > 4.3.9.2 When compressing files, compressed and uncompressed sizes SHOULD be stored in ZIP64
  > format (as 8 byte values) when a file's size exceeds 0xFFFFFFFF.   However ZIP64 format MAY be
  > used regardless of the size of a file.  When extracting, if the zip64 extended information
  > extra field is present for the file the compressed and uncompressed sizes will be 8 byte values.

  Therefore we will always emit the Zip64 representation.

  ## Structure

  ### Shared Zip64 Extended Information

  Size     | Content
  -------- | -
  2 bytes  | Signature
  2 bytes  | Size of Rest of Field (Bytes)
  8 bytes  | Original Size (Bytes)
  8 bytes  | Compressed Size (Bytes)
  8 bytes  | Offset of Local File Header (Bytes)
  """

  @type t :: %__MODULE__{
          size: non_neg_integer(),
          size_compressed: non_neg_integer(),
          offset: non_neg_integer()
        }

  @enforce_keys ~w(size size_compressed offset)a
  defstruct size: 0, size_compressed: 0, offset: 0
end

defimpl Packmatic.Field, for: Packmatic.Field.Shared.ExtendedInformation do
  import Packmatic.Field.Helpers

  def encode(target) do
    [
      <<0x01, 0x00>>,
      encode_16(24),
      encode_64(target.size),
      encode_64(target.size_compressed),
      encode_64(target.offset)
    ]
  end
end
