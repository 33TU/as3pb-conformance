// Command testee-shim is the testee program for the protobuf
// conformance test runner.
//
// The runner speaks the conformance protocol over the testee's
// stdin/stdout (4-byte little-endian length-prefixed ConformanceRequest
// and ConformanceResponse messages). An AIR application cannot do binary
// stdio, so this shim listens on a loopback TCP port, launches the AIR
// testee app via adl with that port as an argument, and proxies raw bytes
// between the runner's pipes and the socket. The framing is identical on
// both legs, so no protobuf parsing happens here.
//
// Usage:
//
//	go build -o bin/testee-shim ./cmd/testee-shim
//	conformance_test_runner --enforce_recommended ./bin/testee-shim
package main

import (
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"syscall"
	"time"
)

func main() {
	adlBin := flag.String("adl", defaultADL(), "path to the adl binary (defaults to $ADL, then $AIR_SDK/bin/adl, then adl on PATH)")
	appXML := flag.String("app", "testee/as3pb-conformance.xml", "AIR application descriptor")
	rootDir := flag.String("root", "testee", "AIR application root directory")
	acceptTimeout := flag.Duration("accept-timeout", 30*time.Second, "how long to wait for the AIR app to connect")
	flag.Parse()

	if err := run(*adlBin, *appXML, *rootDir, *acceptTimeout); err != nil {
		fmt.Fprintln(os.Stderr, "testee-shim:", err)
		os.Exit(1)
	}
}

func defaultADL() string {
	if adl := os.Getenv("ADL"); adl != "" {
		return adl
	}
	return "adl"
}

var appIDPattern = regexp.MustCompile(`<id>[^<]*</id>`)

// uniqueDescriptor writes a copy of appXML whose <id> carries a per-run
// suffix. AIR allows a single instance per application id and forwards new
// invocations to it, and the conformance runner launches a fresh testee per
// suite — without a unique id each launch would race the previous
// instance's teardown.
func uniqueDescriptor(appXML string) (string, error) {
	data, err := os.ReadFile(appXML)
	if err != nil {
		return "", err
	}
	if !appIDPattern.Match(data) {
		return "", fmt.Errorf("no <id> element in %s", appXML)
	}

	suffix := fmt.Sprintf(".p%d.t%d", os.Getpid(), time.Now().UnixNano()%1_000_000_000)
	data = appIDPattern.ReplaceAllFunc(data, func(id []byte) []byte {
		inner := id[len("<id>") : len(id)-len("</id>")]
		return fmt.Appendf(nil, "<id>%s%s</id>", inner, suffix)
	})

	// The descriptor copy must live next to the original: adl may run in a
	// sandbox (e.g. wine via bwrap) that cannot see the system temp dir,
	// and a relative project path is what the wrapper already handles.
	tmp, err := os.CreateTemp(filepath.Dir(appXML), ".descriptor-*.xml")
	if err != nil {
		return "", err
	}
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		os.Remove(tmp.Name())
		return "", err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmp.Name())
		return "", err
	}
	return tmp.Name(), nil
}

func run(adlBin, appXML, rootDir string, acceptTimeout time.Duration) error {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return err
	}
	defer ln.Close()
	port := ln.Addr().(*net.TCPAddr).Port

	uniqueXML, err := uniqueDescriptor(appXML)
	if err != nil {
		return err
	}
	defer os.Remove(uniqueXML)

	cmd := exec.Command(adlBin, uniqueXML, rootDir, "--", strconv.Itoa(port))
	// Stdout must carry nothing but conformance responses, so adl's own
	// output (including trace() from the app) is diverted to stderr.
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	// Own process group: adl forks, and the whole tree must die with us.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("starting adl: %w", err)
	}

	adlExited := make(chan error, 1)
	go func() { adlExited <- cmd.Wait(); close(adlExited) }()

	// Kill the tree and wait until adl is reaped before returning, so the
	// runner never forks the next testee while this one is still dying.
	// (Receiving from the closed channel is instant if adl already exited.)
	defer func() {
		syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		<-adlExited
	}()

	conns := make(chan net.Conn, 1)
	go func() {
		if c, err := ln.Accept(); err == nil {
			conns <- c
		}
	}()

	var conn net.Conn
	select {
	case conn = <-conns:
	case err := <-adlExited:
		return fmt.Errorf("adl exited before the app connected: %v", err)
	case <-time.After(acceptTimeout):
		return fmt.Errorf("timed out after %v waiting for the AIR app to connect on port %d", acceptTimeout, port)
	}
	defer conn.Close()

	stdinDone := make(chan struct{})
	connDone := make(chan struct{})
	go func() {
		io.Copy(conn, os.Stdin)
		conn.(*net.TCPConn).CloseWrite()
		close(stdinDone)
	}()
	go func() {
		io.Copy(os.Stdout, conn)
		close(connDone)
	}()

	select {
	case <-connDone:
		// No more responses can come. That's normal after the runner has
		// finished sending, but means the app died or bailed if requests
		// were still flowing.
		select {
		case <-stdinDone:
			return nil
		default:
			return fmt.Errorf("the app closed the connection while requests were still pending")
		}
	case err := <-adlExited:
		return fmt.Errorf("adl exited mid-run: %v", err)
	case <-stdinDone:
		// The runner is done sending; give in-flight responses a moment.
		select {
		case <-connDone:
		case <-time.After(2 * time.Second):
		}
		return nil
	}
}
