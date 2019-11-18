defmodule Packmatic.Field.Central.FileHeader do
  @moduledoc """
  Represents the Central Directory File Header, which is part of the Central Directory that is
  emitted after all successfully encoded files have been incorporated into the Zip stream.

  ## Structure

  ### Central Directory File Header

  Size     | Content
  -------- | -
  4 bytes  | Signature
  1 byte   | Version made by - Zip Specification Version
  1 byte   | Version made by - Environment
  2 bytes  | Version needed to extract
  2 bytes  | General Purpose Flag
  2 bytes  | Compression Method (0 = No Compression; 8 = Deflated)
  2 bytes  | Modification Time (DOS Format)
  2 bytes  | Modification Date (DOS Format)
  4 bytes  | Checksum (CRC-32)
  4 bytes  | Compressed Size (Placeholder; value set in Zip64 Extended Information Extra Field)
  4 bytes  | Original Size (Placeholder; value set in Zip64 Extended Information Extra Field)
  2 bytes  | File Path Length (Bytes)
  2 bytes  | Extra Fields Length (Bytes)
  2 bytes  | File Comment Length (Bytes)
  2 bytes  | Starting Disk Number for File
  2 bytes  | Internal Attrbutes
  4 bytes  | External Attrbutes
  4 bytes  | Offset of Local File Header
  Variable | File Path
  Variable | Extra Fields
  Variable | File Comment

  #### Notes

  1.  The General Purpose Flag has the following bits set.

      - Bit 3: Indicating a Streaming Archive; Data Descriptor is used, and the Local File Header
        has no Size or CRC information.
      - Bit 11: Language encoding flag, indicating that the Filename and Comment are both already
        in UTF-8. As per APPNOTE, the presence of this flag obviates the need to emit a separate
        Info-ZIP Unicode Path Extra Field.

  2.  The Compressed Size and Original Size fields are both set to `0xFF 0xFF 0xFF 0xFF`, in order
      to force the real sizes, set in the Zip64 Extended Information Extra Field (provided by
      `Packmatic.Field.Shared.ExtendedInformation`) to be used.

  3.  The following Extra Fields are emitted:

      - Extended Timestamp, see `Packmatic.Field.Shared.ExtendedTimestamp`
      - Zip64 Extended Information, see `Packmatic.Field.Shared.ExtendedInformation`

  4.  File comments are not emitted by Packmatic.
  """

  @type t :: %__MODULE__{
          offset: non_neg_integer(),
          path: Path.t(),
          size_compressed: non_neg_integer(),
          size: non_neg_integer(),
          timestamp: DateTime.t()
        }

  @enforce_keys ~w(offset path checksum size_compressed size timestamp)a
  defstruct offset: 0, path: nil, checksum: 0, size_compressed: 0, size: 0, timestamp: nil
end

defimpl Packmatic.Field, for: Packmatic.Field.Central.FileHeader do
  import Packmatic.Field.Helpers
  alias Packmatic.Field

  def encode(target) do
    entry_timestamp = encode_timestamp(target)
    entry_extra_timestamp = encode_extended_timestamp(target)
    entry_extra_zip64 = encode_zip64_info(target)
    entry_extras = [entry_extra_timestamp, entry_extra_zip64]

    [
      <<0x50, 0x4B, 0x01, 0x02>>,
      encode_8(45),
      encode_8(3),
      encode_16(45),
      encode_16(2056),
      encode_16(8),
      entry_timestamp,
      encode_32(target.checksum),
      <<0xFF, 0xFF, 0xFF, 0xFF>>,
      <<0xFF, 0xFF, 0xFF, 0xFF>>,
      encode_16(:erlang.iolist_size(target.path)),
      encode_16(:erlang.iolist_size(entry_extras)),
      encode_16(0),
      encode_16(0),
      encode_16(0),
      encode_32(0),
      encode_32(target.offset),
      target.path,
      entry_extras
    ]
  end

  defp encode_timestamp(target) do
    Field.encode(%Field.Shared.Timestamp{
      timestamp: target.timestamp
    })
  end

  defp encode_extended_timestamp(target) do
    Field.encode(%Field.Shared.ExtendedTimestamp{
      timestamp: target.timestamp
    })
  end

  defp encode_zip64_info(target) do
    Field.encode(%Field.Shared.ExtendedInformation{
      size: target.size,
      size_compressed: target.size_compressed
    })
  end
end
