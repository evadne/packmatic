defmodule Packmatic.Field.Local.FileHeader do
  @moduledoc """
  Represents the Local File Header, which is emitted before the content of each file is
  incorporated into the Zip stream.

  ## Structure

  ### Local File Header

  Size     | Content
  -------- | -
  4 bytes  | Signature
  2 bytes  | Version needed to extract
  2 bytes  | General Purpose Flag
  2 bytes  | Compression Method (0 = No Compression; 8 = Deflated)
  2 bytes  | Modification Time (DOS Format)
  2 bytes  | Modification Date (DOS Format)
  4 bytes  | Checksum (CRC-32; 0 since Data Descriptor is used)
  4 bytes  | Compressed Size (Bytes; 0 since Data Descriptor is used)
  4 bytes  | Original Size (Bytes; 0 since Data Descriptor is used)
  2 bytes  | File Path Length (Bytes)
  2 bytes  | Extra Fields Length (Bytes)
  Variable | File Path
  Variable | Extra Fields

  #### Notes

  1.  The General Purpose Flag has the following bits set.

      - Bit 3: Indicating a Streaming Archive; Data Descriptor is used, and the Local File Header
        has no Size or CRC information.

      - Bit 11: Language encoding flag, indicating that the Filename and Comment are both already
        in UTF-8. As per APPNOTE, the presence of this flag obviates the need to emit a separate
        Info-ZIP Unicode Path Extra Field.

  2.  The Checksum, Compressed Size and Original Size fields are set to 0, since when the Local
      File Header is written, no further data has been read and so this information is not
      available. When the file has been read fully, a Data Descriptor will be written, which
      contains relevant information.

  3.  The following Extra Field is emitted:

      - Extended Timestamp, see `Packmatic.Field.Shared.ExtendedTimestamp`
  """

  alias Packmatic.Manifest.Entry
  @type t :: %__MODULE__{path: Path.t(), timestamp: DateTime.t(), method: Entry.method()}
  defstruct path: nil, timestamp: nil, method: :deflate
end

defimpl Packmatic.Field, for: Packmatic.Field.Local.FileHeader do
  import Packmatic.Field.Helpers
  alias Packmatic.Field

  def encode(%{timestamp: %DateTime{time_zone: "Etc/UTC"}} = target) do
    entry_timestamp = encode_timestamp(target)
    entry_extra_timestamp = encode_extended_timestamp(target)
    entry_extras = [entry_extra_timestamp]

    [
      <<0x50, 0x4B, 0x03, 0x04>>,
      encode_16(45),
      encode_16(2056),
      encode_compression_method(target),
      entry_timestamp,
      encode_32(0),
      encode_32(0),
      encode_32(0),
      encode_16(:erlang.iolist_size(target.path)),
      encode_16(:erlang.iolist_size(entry_extras)),
      target.path,
      entry_extras
    ]
  end

  defp encode_compression_method(%@for{method: method}) do
    case method do
      :store -> encode_16(0)
      :deflate -> encode_16(8)
      {:deflate, _options} -> encode_16(8)
    end
  end

  defp encode_timestamp(target) do
    @protocol.encode(%Field.Shared.Timestamp{
      timestamp: target.timestamp
    })
  end

  defp encode_extended_timestamp(target) do
    @protocol.encode(%Field.Shared.ExtendedTimestamp{
      timestamp: target.timestamp
    })
  end
end
