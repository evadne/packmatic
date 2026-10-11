package main

import (
	"archive/zip"
	"fmt"
	"io"
	"os"
)

func main() {
	if len(os.Args) != 2 {
		panic("usage: go run zip64_decoder_probe.go archive.zip")
	}

	archive, err := zip.OpenReader(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer archive.Close()

	for _, file := range archive.File {
		input, err := file.Open()
		if err != nil {
			panic(err)
		}

		size, err := io.Copy(io.Discard, input)
		closeErr := input.Close()
		if err != nil {
			panic(err)
		}
		if closeErr != nil {
			panic(closeErr)
		}

		fmt.Printf("%s\t%d\n", file.Name, size)
	}
}
