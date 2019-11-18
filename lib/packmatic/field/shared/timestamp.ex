defmodule Packmatic.Field.Shared.Timestamp do
  @moduledoc """
  The Shared Timestamp field is emitted in both Local and Central File Headers, and is emitted in
  DOS (FAT) format.

  The time and date components are represented as little-endian, 16-bit integers, though they are
  first built separately

  ## Structure

  Size     | Content
  -------- | -
  2 bytes  | Hour (5 bits), Minute (6 bits), Second / 2 (5 bits)
  2 bytes  | Year Since 1980 (7 bits), Month (4 bits), Day (5 bits)

  ### Notes

  See Erlang/OTP: `:zip.dos_date_time_to_datetime/2`.

  If the Timestamp given is prior to midnight, 1 January, 1980, it is also coerced to midnight, 1
  January, 1980.

  If the Timestamp is on or after midnight, 1 January, 2108, then it can no longer be correctly
  represented within the limitations of the underlying field, and so is coerced to the previous
  representatable tick: 23:58, 31 December, 2107.
  """

  @type t :: %__MODULE__{timestamp: DateTime.t()}
  @enforce_keys ~w(timestamp)a
  defstruct timestamp: nil
end

defimpl Packmatic.Field, for: Packmatic.Field.Shared.Timestamp do
  def encode(%{timestamp: %DateTime{time_zone: "Etc/UTC"}} = target) do
    encode_datetime(target.timestamp)
  end

  defp encode_datetime(%{year: year}) when year >= 2108 do
    encode_datetime(DateTime.from_naive!(~N[2107-12-31 23:59:58], "Etc/UTC"))
  end

  defp encode_datetime(%{year: year}) when year < 1980 do
    encode_datetime(DateTime.from_naive!(~N[1980-01-01 00:00:00], "Etc/UTC"))
  end

  defp encode_datetime(datetime) do
    <<time::size(16)-big>> = <<
      datetime.hour::size(5)-big,
      datetime.minute::size(6)-big,
      div(datetime.second, 2)::size(5)-big
    >>

    <<date::size(16)-big>> = <<
      datetime.year - 1980::size(7)-big,
      datetime.month::size(4)-big,
      datetime.day::size(5)-big
    >>

    <<time::size(16)-little, date::size(16)-little>>
  end
end
