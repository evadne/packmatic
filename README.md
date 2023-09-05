# Packmatic

**Packmatic** generates Zip streams by aggregating File or URL Sources.

By using a Stream, the caller can compose it within the confines of Plug’s request/response model and serve the content of the resultant Zip archive in a streaming fashion. This allows fast delivery of a Zip archive consisting of many disparate parts hosted in different places, without having to first spool all of them to disk.

The generated archive uses Zip64, and works with individual files that are larger than 4GB. See the Compatibility section for more information.

* * *

- [Design Rationale](#design-rationale)
- [Installation](#installation)
- [Usage](#usage)
- [Source Types](#source-types)
- [Events](#events)
- [Notes](#notes)

* * *

## Design Rationale

### Problem

In modern Web applications, content is often stored away from the host, such as Amazon S3, to enable better scalability and resiliency, as data would not be lost should a particular host go down. However, one disadvantage of this design is that data has become more spread-out, so previously simple operations such as creation of a Zip archive consisting of various files is now more complicated.

In a hypothetical scenario where the developer opts for synchronous generation, the process may spend too long preparing the constituent files, which breaks certain connection proxies which expect a reasonable time to first byte. And in any case, disk utilisation will be high, since not only does each constituent file need to be on disk, there must be free space that will hold the archive temporarily as well.

In another hypothetical scenario, where the developer opts for asynchronous generation, spooling still has to happen and further infrastructure for background job execution, user notification, temporary storage, etc. is now needed, which increases complexity.

### Solution

The overall goal for Packmatic is to deliver a modern Zip streamer, which is able to assemble a Zip file from various sources, such as HTTP(S) downloads or locally generated temporary files, on-the-fly, so as to minimise waiting time, reduce resource consumption and elevate customer happiness.

Packmatic solves the problem by separating the concerns of content definition (specifying what content should be retrieved, and from where), data retrieval (getting the content from the given source), and content presentation (creation of the Archive bundle).

With Packmatic, the developer first specifies a list of Source Entries, which indicates where content can be obtained, and in what way: downloaded from the Internet, read from the filesystem, or dynamically resolved when the archive is being built, etc. This information is then wrapped in a Stream, which is consumed to send out chunked responses.

When the Stream is started, it spins up an Encoder process, which works in a staged, iterative manner. This allows downloads to start almost immediately, which enhances customer happiness.

The Encoder consumes the manifest as the Stream is consumed. In other words, the Stream starts producing data only when the client starts reading, and only as fast as the client reads, which reduces the amount of networking and local storage needed to start the process. Most of the acquisition work is interleaved, and back-pressured by client connection speed.

### Benefits

Since Packmatic only streams what it needs, and does not spool content locally, it is possible to produce large archives whose constituent files do not fit on one host. This is an advantage over conventional processes, where even in a synchronous scenario, all constituent files _and the archive_ must be spooled to disk.

This design enhances developer happiness as well, since by using a synchronous, iterative mode of operation, there is no longer any need to spool constituent files in the archive on disk; there is also no longer any need to build technical workarounds in order to compensate for archive preparation delays.

With Packmatic, both the problem and the solution is drastically simplified. The user clicks “download”, and the archive starts downloading. This is how it should be.

## Installation

To install Packmatic, add the following line in your application’s dependencies:

```elixir
defp deps do
  [
    {:packmatic, "~> 1.1.3"}
  ]
end
```

## Usage

The general way to use Packmatic within your application is to generate a `Stream` dynamically by passing a list of Source Entries directly to `Packmatic.build_stream/2`. This gives you a standard Stream which you can then send it off for download with help from `Packmatic.Conn.send_chunked/3`.

If you need more control, for example if you desire context separation, or if you wish to validate that the entries are valid prior to vending a Stream, you may generate a `Packmatic.Manifest` struct ahead of time, then pass it to `Packmatic.build_stream/2` at a later time. See `Packmatic.Manifest` for more information.

In either case, the Stream is powered by `Packmatic.Encoder`, which consumes the Entries within the Manifest iteratively as the Stream is consumed, at the pace set by the client’s download connection.

### Building the Stream with Entries

The usual way to construct a Stream is as follows.

```elixir
entries = [
  [source: {:file, "/tmp/hello.pdf"}, path: "hello.pdf"],
  [source: {:file, "/tmp/world.pdf"}, path: "world.pdf", timestamp: DateTime.utc_now()],
  [source: {:url, "https://example.com/foo.pdf"}, path: "foo/bar.pdf"]
]

stream = Packmatic.build_stream(entries)
```

As you can see, each Entry used to build the Stream (under `source:`) is a keyword list, which concerns itself with the source, the path, and optionally a timestamp:

-  `source:` represents a 2-arity tuple, representing the name of the Source and its Initialisation Argument. This data structure specifies the nature of the data, and how to obtain its content.

-  `path:` represents the path in the Zip file that the content should be put under; it is your own responsibility to ensure that paths are not duplicated (see the Notes for an example).

-  `timestamp:` is optional, and represents the creation/modification timestamp of the file. Packmatic emits both the basic form (DOS / FAT) of the timestamp, and the Extended Timestamp Extra Field which represents the same value with higher precision and range.

Packmatic supports reading from any Source which conforms to the `Packmatic.Source` behaviour. To aid adoption and general implementation, there are built-in Sources as well; this is documented under [Source Types](#source-types). 

### Building a Manifest

If you wish, you can use the `Packmatic.Manifest` module to build a Manifest ahead-of-time, in order to validate the Entries prior to vending the Stream.

Manifests can be created iteratively by calling `Packmatic.Manifest.prepend/2` against an existing Manifest, or by calling `Packmatic.Manifest.create/1` with a list of Entries created elsewhere. For more information, see `Packmatic.Manifest`.

### Specifying Error Behaviour

By default, Packmatic fails the Stream when any Entry fails to process for any reason. If you desire, you may pass an additional option to `Packmatic.build_stream/2` in order to modify this behaviour:

```elixir
stream = Packmatic.build_stream(entries, on_error: :skip)
```

### Writing Stream to File

You can use the standard `Stream.into/2` call to operate on the Stream:

```elixir
stream
|> Stream.into(File.stream!(file_path, [:write]))
|> Stream.run()
```

### Writing Stream to Conn (with Plug)

You can use the bundled `Packmatic.Conn` module to send a Packmatic stream down the wire:

```elixir
stream
|> Packmatic.Conn.send_chunked(conn, "download.zip")
```

When writing the stream to a chunked `Plug.Conn`, Packmatic automatically escapes relevant characters in the name and sets the Content Disposition to `attachment` for maximum browser compatibility under intended use.

## Source Types

Packmatic has default Source types that you can use easily when building Manifests and/or Streams:

1.  **File,** representing content on disk, useful when the content is already available and only needs to be integrated. See `Packmatic.Source.File`.

2.  **URL,** representing content that is available remotely. Packmatic will run a chunked download routine to incrementally download and archive available chunks. See `Packmatic.Source.URL`.

3.  **Stream,** representing content that is generated by a Stream (perhaps from other libraries) which can be incrementally consumed and incorporated in the archive. Anything that conforms to the Enumerable protocol, for example a List containing binaries, can be passed as well.

4.  **Random,** representing randomly generated bytes which is useful for testing. See `Packmatic.Source.Random`.

5.  **Dynamic,** representing a dynamically resolved Source, which is ultimately fulfilled by pulling content from either a File or an URL. If you have any need to inject a dynamically generated file, you may use this Source type to do it. This also has the benefit of avoiding expensive computation work in case the customer abandons the download midway. See `Packmatic.Source.Dynamic`.

These Streams can be referred by their internal aliases:

- `{:file, "/tmp/hello/pdf"}`.
- `{:url, "https://example.com/hello/pdf"}`.
- `{:stream, [<<0>>, <<1>>]}`.
- `{:random, 1048576}`.
- `{:dynamic, fn -> {:ok, {:random, 1048576}} end}`.

Alternatively, they can also be referred by module names:

- `{Packmatic.Source.File, "/tmp/hello/pdf"}`.
- `{Packmatic.Source.URL, "https://example.com/hello/pdf"}`.
- `{Packmatic.Source.Stream, enum}`.
- `{Packmatic.Source.Random, 1048576}`.
- `{Packmatic.Source.Dynamic, fn -> {:ok, {:random, 1048576}} end}`.

### Dynamic & Custom Sources

If you have an use case where you wish to dynamically generate the content that goes into the archive, you may either use the Dynamic source or implement a Custom Source.

For example, if the amount of dynamic computation is small, but the results are time-sensitive, like when you already have Object IDs and just need to pre-sign URLs, you can use a Dynamic source with a curried function:

    {:dynamic, MyApp.Packmatic.build_dynamic_fun(object_id)}

If you have a different use case, for example if you need to pull data from a FTP server (which uses a protocol that Packmatic does not have a bundled Source to work with), you can implement a module that conforms to the `Packmatic.Source` behaviour, and pass it:

    {MyApp.Packmatic.Source.FTP, "ftp://example.com/my.docx"}

See `Packmatic.Source` for more information.

## Events

The Encoder can be configured to emit events in order to enable feedback elsewhere in your application, for example:

```elixir
entries = [
  [source: {:file, "/tmp/hello.pdf"}, path: "hello.pdf"],
  [source: {:file, "/tmp/world.pdf"}, path: "world.pdf", timestamp: DateTime.utc_now()],
  [source: {:url, "https://example.com/foo.pdf"}, path: "foo/bar.pdf"]
]

entries_count = length(entries)
entries_completed_agent = Agent.start(fn -> 0 end)

handler_fun = fn event ->
  case event do
    %Packmatic.Event.EntryCompleted{} ->
      count = Agent.get_and_update(entries_completed_agent, & &1 + 1)
      IO.puts "#{count} of #{entries_count} encoded"
    %Packmatic.Event.StreamEnded{} ->
      :ok = Agent.stop(entries_completed_agent)
      :ok
    _ ->
      :ok
  end
end

stream = Packmatic.build_stream(entries, on_event: handler_fun)
```

See documentation for `Packmatic.Event` for a complete list of Event types.

## Notes

1.  As with any user-generated content, you should exercise caution when building the Manifest, and ensure that only content that the User is entitled to retrieve is included.

2.  Due to design limitations, when downloading resources via a HTTP(S) connection, should the connection become closed halfway, a partial representation may be embedded in the output. A future release of this library may correct this in case the `Content-Length` header is present in the output, and act accordingly.

3.  You must ensure that paths are not duplicated within the same Manifest. You can do this by first building a list of sources and paths, then grouping and numbering them as needed with `Enum.group_by/3`.

    Given entries are `{source, path}` tuples, you can do this:

    ```elixir
    annotate_fun = fn entries ->
      for {{source, path}, index} <- Enum.with_index(entries) do
        path_components = Path.split(path)
        {path_components, [filename]} = Enum.split(path_components, -1)
        extname = Path.extname(filename)
        basename = Path.basename(filename, extname)
        path_components = path_components ++ ["#{basename} (#{index + 1})#{extname}"]
        {source, Path.join(path_components)}
      end
    end

    duplicates_fun = fn
      [_ | [_ | _]] = entries -> annotate_fun.(entries)
      entries -> entries
    end

    entries
    |> Enum.group_by(& elem(&1, 1))
    |> Enum.flat_map(&duplicates_fun.(elem(&1, 1)))
    ```

4.  You must ensure that paths conform to the target environment of your choice, for example macOS and Windows each has its limitations regarding how long paths can be.

### Compatibility

- Windows
  - Windows Explorer (Windows 10): OK
  - 7-Zip: OK

- macOS
  - Finder (High Sierra): OK
  - The Unarchiver (High Sierra): NG
  - Erlang/OTP (`:zip`): NG

### Known Issues

- Ability to switch between STORE and DEFLATE modes is under investigation. Currently all archives are generated with DEFLATE, although for some use cases, this only increases the size of the archive, as content within each file is already compressed.

- Can not change compression level.

- Explicit directory generation is not supported; each entry must be a file. This is pending further investigation.

- Handling of 0-length files from sources is pending further investigation. Currently, they do get journaled but this may change in the future.

### Future Enhancements

- We will consider adding ability to resume downloads with range queries, so if the URL Source fails we can attempt to resume encoding from where we left off.

- In practice, if there are large files that are archived repeatedly, they will be pulled repeatedly and there is currently no explicit ability to cache them. We expect that in these cases an optimisation by the application developer may be to temporarily spool these hot constituents on disk and use a Dynamic Source to wrap around the cache layer (which would emit a File Source if the file is available locally, and act accordingly otherwise).

## Acknowledgements

During design and prototype development of this library, the Author has drawn inspiration from the following implementations, and therefore thanks all contributors for their generosity:

- [ctrabant/fdzipstream](https://github.com/CTrabant/fdzipstream)
- [dgvncsz0f/zipflow](https://github.com/dgvncsz0f/zipflow)

The Author wishes to thank the following individuals:

- [Alvise Susmel][alvises] for proposing and testing [Encoder Events][gh-3]
- [Christoph Geschwind][1st8] for highlighting [the need for explicit cleanup logic][gh-8]

## Reference

- https://users.cs.jmu.edu/buchhofp/forensics/formats/pkzip.html
- https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT

[1st8]: https://github.com/1st8
[alvises]: https://github.com/alvises
[gh-3]: https://github.com/evadne/packmatic/issues/3
[gh-8]: https://github.com/evadne/packmatic/pull/8
