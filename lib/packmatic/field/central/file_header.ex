defmodule Packmatic.Field.Central.FileHeader do
  @moduledoc """
  Represents the Central Directory File Header, which is part of the Central Directory at the
  end of the archive.

  The Central Directory is emitted after all successfully encoded files have been incorporated
  into the Zip stream. It contains one Central Directory File Header for each encoded file and
  a single End of Central Directory record.

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
  4 bytes  | Compressed Size (Placeholder to force Zip64)
  4 bytes  | Original Size (Placeholder to force Zip64)
  2 bytes  | File Path Length (Bytes)
  2 bytes  | Extra Fields Length (Bytes)
  2 bytes  | File Comment Length (Bytes)
  2 bytes  | Starting Disk Number for File
  2 bytes  | Internal Attrbutes
  4 bytes  | External Attrbutes
  4 bytes  | Offset of Local File Header (Placeholder to force Zip64)
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

  2.  The Compressed Size and Original Size fields are both 4-byte fields, meaning the maximum
      value is `0xFF 0xFF 0xFF 0xFF` in case of overflow, however we will not use these fields,
      because the Zip version 4.5 is already required, which implies that the client must support
      Zip64. The real sizes are always set again in the Zip64 Extended Information Extra Field,
      which uses 8-byte fields, as provided by `Packmatic.Field.Shared.ExtendedInformation`.

  3.  If the Entry has both the UID and GID attributes set then this will be emitted in an Extra
      Field, otherwise said field will not be emitted.

  4.  The following Extra Fields are emitted:

      - Extended Timestamp, see `Packmatic.Field.Shared.ExtendedTimestamp`
      - Zip64 Extended Information, see `Packmatic.Field.Shared.ExtendedInformation`
      - UNIX UID/GID Information, see `Packmatic.Field.Shared.Unix`

  5.  File comments are not emitted by Packmatic.
  """

  alias Packmatic.Manifest.Entry
  alias Packmatic.Manifest.Entry.Attributes

  @type t :: %__MODULE__{
          offset: non_neg_integer(),
          path: Path.t(),
          checksum: non_neg_integer(),
          size_compressed: non_neg_integer(),
          size: non_neg_integer(),
          timestamp: DateTime.t(),
          attributes: Attributes.t(),
          method: Entry.method()
        }

  @enforce_keys ~w(offset path checksum size_compressed size timestamp attributes method)a
  defstruct offset: 0,
            path: nil,
            checksum: 0,
            size_compressed: 0,
            size: 0,
            timestamp: nil,
            attributes: %Attributes{},
            method: :deflate
end

defimpl Packmatic.Field, for: Packmatic.Field.Central.FileHeader do
  import Packmatic.Field.Helpers
  alias Packmatic.Field

  def encode(target) do
    import Bitwise

    entry_extra_timestamp = encode_extended_timestamp(target)
    entry_extra_information = encode_extended_information(target)
    entry_extra_unix = encode_unix(target)
    entry_extras = [entry_extra_timestamp, entry_extra_information, entry_extra_unix]

    external_attribute_value =
      [
        # S_IFREG - regular file
        0o100000,
        (target.attributes.setuid && 0o004000) || 0o0,
        (target.attributes.setgid && 0o002000) || 0o0,
        (target.attributes.sticky && 0o001000) || 0o0,
        target.attributes.mode
      ]
      |> Enum.reduce(&Bitwise.|||/2)

    [
      <<0x50, 0x4B, 0x01, 0x02>>,
      encode_8(45),
      encode_8(3),
      encode_16(45),
      encode_16(2056),
      encode_compression_method(target),
      encode_timestamp(target),
      encode_32(target.checksum),
      <<0xFF, 0xFF, 0xFF, 0xFF>>,
      <<0xFF, 0xFF, 0xFF, 0xFF>>,
      encode_16(:erlang.iolist_size(target.path)),
      encode_16(:erlang.iolist_size(entry_extras)),
      encode_16(0),
      encode_16(0),
      encode_16(0),
      encode_32(external_attribute_value <<< 16),
      <<0xFF, 0xFF, 0xFF, 0xFF>>,
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

  defp encode_timestamp(%@for{} = target) do
    @protocol.encode(%Field.Shared.Timestamp{
      timestamp: target.timestamp
    })
  end

  defp encode_extended_timestamp(%@for{} = target) do
    @protocol.encode(%Field.Shared.ExtendedTimestamp{
      timestamp: target.timestamp
    })
  end

  defp encode_extended_information(%@for{} = target) do
    @protocol.encode(%Field.Shared.ExtendedInformation{
      size: target.size,
      size_compressed: target.size_compressed,
      offset: target.offset
    })
  end

  defp encode_unix(%@for{} = target) do
    if should_encode_unix?(target) do
      @protocol.encode(%Field.Shared.Unix{
        uid: target.attributes.uid,
        gid: target.attributes.gid
      })
    else
      []
    end
  end

  defp should_encode_unix?(%@for{} = target) do
    cond do
      is_nil(target.attributes.uid) -> false
      is_nil(target.attributes.gid) -> false
      true -> true
    end
  end
end
