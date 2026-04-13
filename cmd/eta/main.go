package main

import (
	"os"

	"github.com/Sorix/eta/internal/eta"
)

func main() {
	os.Exit(eta.Main(os.Args[1:]))
}
