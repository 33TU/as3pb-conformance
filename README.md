# as3pb-conformance

Runs the official [protobuf conformance suite](https://github.com/protocolbuffers/protobuf/tree/main/conformance)
against [as3pb](https://github.com/33TU/as3pb), the ActionScript 3
Protocol Buffers library, executing inside the Adobe AIR runtime.

## How it works

The conformance runner speaks a simple protocol over the testee's
stdin/stdout: 4-byte little-endian length-prefixed `ConformanceRequest`
and `ConformanceResponse` messages. An AIR application cannot do binary
stdio, so the testee is split in two:

```
conformance_test_runner ⇄ stdio ⇄ testee-shim (Go) ⇄ TCP ⇄ AIR app (adl)
```

`cmd/testee-shim` listens on a loopback port, launches the AIR app via
`adl` with that port as an argument, and proxies raw bytes between the
runner's pipes and the socket — the framing is identical on both legs.
Each launch uses a per-run copy of the app descriptor with a unique
`<id>`, because AIR enforces a single instance per application id and
the runner forks a fresh testee for every suite.

`testee/src/Main.as` connects back to the shim, deserializes each
request with the as3pb-generated classes, and round-trips
`TestAllTypesProto3` through the as3pb runtime.

The protobuf submodule pins the suite version; both the conformance
protos fed to codegen and the runner build come from that checkout.

## Prerequisites

- Go, [just](https://github.com/casey/just), CMake, and `protoc`
- An AIR SDK with `adl` and `amxmlc` on `PATH` (override with the
  `ADL`/`AMXMLC` env vars)
- Submodules: `git clone --recurse-submodules`, or
  `git submodule update --init`

## Usage

```sh
just build-runner        # one-time: build conformance_test_runner from the protobuf submodule
just gen                 # regenerate AS3 from the conformance protos (after as3pb codegen changes)
just test                # build the shim and testee, run the suite
just update-submodules   # as3pb to latest main; protobuf stays at its pin
```

## Scope and status

Only the proto3 binary wire format is graded; JSON, text format, and
proto2 requests are answered with `skipped`. Known as3pb gaps are
tracked in `expected_failures.txt`:

- invalid UTF-8 in proto3 string fields is accepted

## Results

**as3pb passes the proto3 binary wire-format conformance tests** —
702 tests, 0 unexpected failures against protobuf v35.1. The only
exceptions are the 5 expected failures from the UTF-8 gap listed
above; the skips are the JSON, proto2, editions, and text-format tests
outside the suite's graded scope here.

```
CONFORMANCE SUITE PASSED: 702 successes, 2101 skipped, 5 expected failures, 0 unexpected failures.
CONFORMANCE SUITE PASSED: 0 successes, 445 skipped, 0 expected failures, 0 unexpected failures.
```
