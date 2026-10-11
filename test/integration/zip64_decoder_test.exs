defmodule Packmatic.Integration.Zip64DecoderTest do
  use ExUnit.Case, async: false

  @moduletag integration: true
  @moduletag timeout: 300_000

  @expected "large.bin\t4296015872\nmarker.txt\t9\n"
  @support_directory __DIR__

  setup_all do
    {:ok, archive_path} = Briefly.create()
    chunk = :binary.copy(<<0>>, 1_048_576)

    entries = [
      [
        source: {:stream, Stream.repeatedly(fn -> chunk end) |> Stream.take(4097)},
        path: "large.bin"
      ],
      [source: {:stream, ["packmatic"]}, path: "marker.txt"]
    ]

    entries
    |> Packmatic.Manifest.create()
    |> Packmatic.build_stream()
    |> Stream.into(File.stream!(archive_path, [:write]))
    |> Stream.run()

    [archive_path: archive_path]
  end

  test "system unzip validates the archive", %{archive_path: archive_path} do
    assert_success("unzip", ["-t", archive_path])
  end

  test "7-Zip validates the archive", %{archive_path: archive_path} do
    assert_success("7z", ["t", "-bd", "-bb0", archive_path])
  end

  test "libarchive reads every entry through the central directory", %{
    archive_path: archive_path
  } do
    assert_success("sh", [
      "-c",
      ~S|exec bsdtar -xOf "$1" > /dev/null|,
      "sh",
      archive_path
    ])
  end

  test "Java ZipInputStream reads every entry in a single pass", %{archive_path: archive_path} do
    assert @expected ==
             run_probe("java", ["Zip64DecoderProbe.java", "stream", archive_path])
  end

  test "Java ZipFile reads every entry through the central directory", %{
    archive_path: archive_path
  } do
    assert @expected == run_probe("java", ["Zip64DecoderProbe.java", "seek", archive_path])
  end

  test "Go archive/zip reads every entry through the central directory", %{
    archive_path: archive_path
  } do
    assert @expected == run_probe("go", ["run", "zip64_decoder_probe.go", archive_path])
  end

  defp assert_success(command, arguments) do
    {output, status} = System.cmd(command, arguments, stderr_to_stdout: true)

    assert status == 0, "#{command} failed with status #{status}:\n#{output}"
  end

  defp run_probe(command, arguments) do
    {output, status} = System.cmd(command, arguments, cd: @support_directory)

    assert status == 0, "#{command} failed with status #{status}:\n#{output}"
    output
  end
end
