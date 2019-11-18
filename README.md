# Packmatic

**Packmatic** generates Zip streams by aggregating File or URL Sources.

By using a Stream, the caller can compose it within the confines of Plug’s request/response model and serve the content of the resultant Zip archive in a streaming fashion. This allows fast delivery of a Zip archive consisting of many disparate parts hosted in different places, without having to first spool all of them to disk.

The generated archive uses Zip64, and works with individual files that are larger than 4GB. See the Compatibility section for more information.

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

    defp deps do
      [
        {:packmatic, "~> 0.1.0"}
      ]
    end

## Usage

In order to use Packmatic, you will first create such a Stream by `Packmatic.build_stream/2`. You can then send it off for download with help from `Packmatic.Conn.send_chunked/3`.

Internally, this is powered by `Packmatic.Encoder`, which consumes the Entries within a built Manifest iteratively at the pace set by the client’s download connection.

Each Source Entry within the Manifest specifies the source from where to obtain the content of a particular file to be placed in the package, and which path to put it under; it is your own responsibility to ensure that paths are not duplicated (see the Notes for an example).

### Building Stream

The usual way to construct a Stream is as follows.

    entries = [
      [source: {:file, "/tmp/hello.pdf"}, path: "hello.pdf"],
      [source: {:file, "/tmp/world.pdf"}, path: "world.pdf"],
      [source: {:url, "https://example.com/foo.pdf"}, path: "foo/bar.pdf"]
    ]
    
    stream = Packmatic.build_stream(entries)

If you desire, you may pass an additional option entry to `Packmatic.build_stream/2`, such as:

    stream = Packmatic.build_stream(entries, on_error: :skip)

Each Entry used to build the Stream is a 2-arity tuple, representing the Source Entry and the Path for the file.

Further, the Source Entry is a 2-arity tuple which represents the type of Source and the initialising argument of that type of Source. See [Source Types](#source-types).

### Writing Stream to File

    stream
    |> Stream.into(File.stream!(file_path, [:write]))
    |> Stream.run()

### Writing Stream to Conn (with Plug)

    stream
    |> Packmatic.Conn.send_chunked(conn, "download.zip")

When writing the stream to a chunked `Plug.Conn`, Packmatic automatically escapes relevant characters in the name and sets the Content Disposition to `attachment` for maximum browser compatibility under intended use.

## Source Types

Within Packmatic, there are four types of Sources:

1.  **File,** representing content on disk, useful when the content is already available and only needs to be integrated.

    Example: `{:file, "/tmp/hello/pdf"}`.

    See `Packmatic.Source.File`.

2.  **URL,** representing content that is available remotely. Packmatic will run a chunked download routine to incrementally download and archive available chunks.

    Example: `{:url, "https://example.com/hello/pdf"}`.

    See `Packmatic.Source.URL`.

3.  **Random,** representing randomly generated bytes which is useful for testing.

    Example: `{:random, 1048576}`.

    See `Packmatic.Source.Random`.

4.  **Dynamic,** representing a dynamically resolved Source, which is ultimately fulfilled by pulling content from either a File or an URL. If you have any need to inject a dynamically generated file, you may use this Source type to do it. This also has the benefit of avoiding expensive computation work in case the customer abandons the download midway.

    Example: `{:dynamic, fn -> {:ok, {:random, 1048576}} end}`.

    See `Packmatic.Source.Dynamic`.

## Notes

1.  As with any user-generated content, you should exercise caution when building the Manifest, and ensure that only content that the User is entitled to retrieve is included.

2.  Due to design limitations, when downloading resources via a HTTP(S) connection, should the connection become closed halfway, a partial representation may be embedded in the output. A future release of this library may correct this in case the `Content-Length` header is present in the output, and act accordingly.

3.  You must ensure that paths are not duplicated within the same Manifest. You can do this by first building a list of sources and paths, then grouping and numbering them as needed with `Enum.group_by/3`.

    Given entries are `{source, path}` tuples, you can do this:

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

## Reference

- https://users.cs.jmu.edu/buchhofp/forensics/formats/pkzip.html
- https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
