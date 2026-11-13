//go:build ignore

// Serve the current directory for local mockup previews: go run scripts/serve.go.
package main

import (
	"flag"
	"log"
	"net"
	"net/http"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:8765", "loopback listen address")
	flag.Parse()
	host, _, err := net.SplitHostPort(*addr)
	if err != nil || net.ParseIP(host) == nil || !net.ParseIP(host).IsLoopback() {
		log.Fatal("preview server requires a loopback address")
	}
	log.Printf("Serving current directory at http://%s", *addr)
	log.Fatal(http.ListenAndServe(*addr, http.FileServer(http.Dir("."))))
}
