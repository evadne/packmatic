defmodule Packmatic.Field.Local.DataDescriptorTest do
  use ExUnit.Case, async: true

  alias Packmatic.Field.Local.DataDescriptor

  for {size, compressed, width} <- [
        {0, 0, 32},
        {0xFFFFFFFE, 0xFFFFFFFF, 32},
        {0xFFFFFFFF, 0xFFFFFFFE, 32},
        {0xFFFFFFFF, 0xFFFFFFFF, 32},
        {0x1_0000_0000, 0x01020304, 64},
        {0x01020304, 0x1_0000_0000, 64},
        {0xFFFFFFFF, 0x1_0000_0000, 64},
        {0x1_0000_0000, 0xFFFFFFFF, 64},
        {0x1_0000_0001, 0x1_0000_0000, 64}
      ] do
    test "encodes #{width}-bit sizes for #{size} original and #{compressed} compressed bytes" do
      descriptor = %DataDescriptor{
        checksum: 0xAABBCCDD,
        size_compressed: unquote(compressed),
        size: unquote(size)
      }

      encoded = descriptor |> Packmatic.Field.encode() |> IO.iodata_to_binary()

      assert <<
               0x08074B50::little-32,
               0xAABBCCDD::little-32,
               unquote(compressed)::little-size(unquote(width)),
               unquote(size)::little-size(unquote(width))
             >> == encoded
    end
  end
end
