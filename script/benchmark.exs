# MIX_ENV=test mix run ./script/benchmark.exs

import PackmaticTest.Builder

Incendium.run(%{
  "Random Small" => fn ->   
      {:ok, file_path} = Briefly.create()

      [
        [source: {:random, 8 * 1048576}, path: "1"],
        [source: {:random, 8 * 1048576}, path: "2"],
        [source: {:random, 8 * 1048576}, path: "3"]
      ]
      |> Packmatic.Manifest.create()
      |> Packmatic.build_stream()
      |> Stream.into(File.stream!(file_path, [:write]))
      |> Stream.run()
    end,
    "Deflate and Store" => fn ->
      {:ok, file_path} = Briefly.create()
      
      [
        [source: build_file_source(), path: "1", method: :deflate],
        [source: build_file_source(), path: "2", method: :store],
        [source: build_file_source(), path: "3", method: {:deflate, level: :best_compression}],
        [source: build_file_source(), path: "4", method: :store],
        [source: build_file_source(), path: "5", method: {:deflate, level: :best_speed}]
      ]
      |> Packmatic.Manifest.create()
      |> Packmatic.build_stream()
      |> Stream.into(File.stream!(file_path, [:write]))
      |> Stream.run()
    end
  },
  title: "Packmatic",
  incendium_flamegraph_widths_to_scale: true
)
