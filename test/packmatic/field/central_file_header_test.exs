defmodule Packmatic.Field.Central.FileHeaderTest do
  use ExUnit.Case, async: true

  alias Packmatic.Field
  alias Packmatic.Field.Central
  alias Packmatic.Manifest.Entry.Attributes

  # Regression test for the Zip64 local-header offset (IBLSA-743).
  #
  # In Packmatic <= 1.2.0 the Central Directory File Header wrote the local-header
  # offset with `encode_32/1`. For offsets >= 4 GiB that helper silently falls back
  # to the 0xFFFFFFFF sentinel, but the Zip64 Extended Information field only ever
  # carried the (un)compressed sizes, never the offset. The result: every entry
  # stored past the 4 GiB mark had an unresolvable offset and was reported as
  # corrupted, even though all file data was present.
  #
  # The fix must:
  #   1. set the 32-bit offset field to 0xFFFFFFFF, and
  #   2. emit the real 8-byte offset inside the Zip64 Extended Information field.

  @big_offset 0x1_2345_6789

  defp encode_header(offset) do
    %Central.FileHeader{
      offset: offset,
      path: "big.bin",
      checksum: 0,
      size_compressed: 10,
      size: 10,
      timestamp: ~U[2026-06-22 00:00:00Z],
      attributes: %Attributes{},
      method: :deflate
    }
    |> Field.encode()
    |> :erlang.iolist_to_binary()
  end

  # Pull the fixed-size offset field and the file-path/extra blobs out of a
  # 46-byte Central Directory File Header.
  defp parse(<<
         0x50,
         0x4B,
         0x01,
         0x02,
         _version_made::16-little,
         _version_needed::16-little,
         _flag::16-little,
         _method::16-little,
         _mtime::16-little,
         _mdate::16-little,
         _crc::32-little,
         _size_compressed::32-little,
         _size::32-little,
         path_len::16-little,
         extra_len::16-little,
         _comment_len::16-little,
         _disk::16-little,
         _internal_attr::16-little,
         _external_attr::32-little,
         offset_field::32-little,
         rest::binary
       >>) do
    <<_path::binary-size(path_len), extra::binary-size(extra_len), _::binary>> = rest
    %{offset_field: offset_field, extra: extra}
  end

  # Walk the Extra Field area and return the payload of the Zip64 Extended
  # Information field (tag 0x0001), or nil if absent.
  defp zip64_payload(<<0x01, 0x00, len::16-little, payload::binary-size(len), _::binary>>),
    do: payload

  defp zip64_payload(
         <<_tag::16-little, len::16-little, _payload::binary-size(len), rest::binary>>
       ),
       do: zip64_payload(rest)

  defp zip64_payload(_), do: nil

  test "offsets >= 4 GiB are written as a Zip64 sentinel backed by an 8-byte offset" do
    %{offset_field: offset_field, extra: extra} = parse(encode_header(@big_offset))

    assert offset_field == 0xFFFFFFFF, "32-bit offset field must be the Zip64 sentinel"

    payload = zip64_payload(extra)
    assert payload != nil, "Zip64 Extended Information field must be present"

    # size (8) + compressed size (8) + local header offset (8)
    assert byte_size(payload) == 24,
           "Zip64 extra must carry the 8-byte local-header offset (was #{byte_size(payload)} bytes)"

    <<_size::64-little, _size_compressed::64-little, encoded_offset::64-little>> = payload

    assert encoded_offset == @big_offset,
           "the real local-header offset must round-trip through the Zip64 extra field"
  end

  test "small offsets also round-trip through the Zip64 extra field" do
    offset = 52_443
    %{offset_field: offset_field, extra: extra} = parse(encode_header(offset))

    assert offset_field == 0xFFFFFFFF
    <<_size::64-little, _csize::64-little, encoded_offset::64-little>> = zip64_payload(extra)
    assert encoded_offset == offset
  end
end
