import java.io.BufferedInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Enumeration;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipInputStream;

class Zip64DecoderProbe {
  private static final byte[] BUFFER = new byte[1024 * 1024];

  public static void main(String[] arguments) throws Exception {
    if (arguments.length != 2) {
      throw new IllegalArgumentException("usage: Zip64DecoderProbe.java stream|seek archive.zip");
    }

    switch (arguments[0]) {
      case "stream" -> stream(Path.of(arguments[1]));
      case "seek" -> seek(Path.of(arguments[1]));
      default -> throw new IllegalArgumentException("unknown mode: " + arguments[0]);
    }
  }

  private static void stream(Path archive) throws IOException {
    try (InputStream input = Files.newInputStream(archive);
        ZipInputStream zip = new ZipInputStream(new BufferedInputStream(input))) {
      ZipEntry entry;

      while ((entry = zip.getNextEntry()) != null) {
        System.out.printf("%s\t%d%n", entry.getName(), consume(zip));
        zip.closeEntry();
      }
    }
  }

  private static void seek(Path archive) throws IOException {
    try (ZipFile zip = new ZipFile(archive.toFile())) {
      Enumeration<? extends ZipEntry> entries = zip.entries();

      while (entries.hasMoreElements()) {
        ZipEntry entry = entries.nextElement();

        try (InputStream input = zip.getInputStream(entry)) {
          System.out.printf("%s\t%d%n", entry.getName(), consume(input));
        }
      }
    }
  }

  private static long consume(InputStream input) throws IOException {
    long size = 0;
    int count;

    while ((count = input.read(BUFFER)) != -1) {
      size += count;
    }

    return size;
  }
}
