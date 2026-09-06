# as3pb-conformance

Runs the official [protobuf conformance suite](https://github.com/protocolbuffers/protobuf/tree/main/conformance)
against [as3pb](https://github.com/33TU/as3pb), the ActionScript 3
Protocol Buffers library, executing inside Adobe AIR or Apache Royale/Node.

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

`testee/src/Main.as` connects back to the shim and deserializes requests with
the as3pb-generated classes. `testee/src/ConformanceCodec.as` handles requests
and round-trips `TestAllTypesProto3` for both transports.

The Royale entry point in `testee/royale/Main.as` reads and writes the same
framed protocol directly using Node binary stdio, without the Go/TCP shim.

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

The binary wire format is graded for proto3 and for editions files
using proto3 semantics (`test_messages_proto3_editions.proto`), with
the runner at `--maximum_edition 2024` — the suite defines no tests
above edition 2023, so 2024 adds no wire surface. Beyond the proto3
feature set, as3pb also accepts editions explicit presence and
declared defaults (surfaced as generated `DEFAULT_*` constants for
callers to substitute when the nullable field is unset; both features
are wire-neutral, so no conformance tests exercise them). JSON, text
format, proto2, and the remaining edition-2023 features (extensions,
delimited encoding, closed enums) are answered with `skipped`. Known as3pb gaps are tracked in
`expected_failures.txt`:

- invalid UTF-8 in string fields is accepted (a deliberate tradeoff:
  validation costs a per-byte scan on the string hot path, and as3pb
  is a client library parsing trusted server payloads)

## Results

**as3pb passes the proto3 and editions-proto3 binary wire-format
conformance tests** — 1404 tests, 0 unexpected failures against
protobuf v35.1. The only exceptions are the 10 expected failures from
the UTF-8 stance listed above (5 per message type); the skips are the
JSON, proto2, full-editions, and text-format tests outside the
suite's graded scope here.

```
CONFORMANCE SUITE PASSED: 1404 successes, 4217 skipped, 10 expected failures, 0 unexpected failures.
CONFORMANCE SUITE PASSED: 0 successes, 909 skipped, 0 expected failures, 0 unexpected failures.
```

## Apache Royale / Node

Use the `royale` branch of both this repository and its as3pb submodule.
Requires Node, Java, Bash, Python 3 (transport smoke tests), and Royale 0.9.12,
plus the pinned protobuf runner and generated fixtures described above.

```sh
npm install --prefix "$HOME/.cache/as3pb-royale" @apache-royale/royale-js@0.9.12
export ROYALE_SDK="$HOME/.cache/as3pb-royale/node_modules/@apache-royale/royale-js/royale-asjs"
just test-royale
```

`just build-royale-testee` compiles only. To rerun the suite on that bundle:

```sh
tools/conformance_test_runner --enforce_recommended --maximum_edition 2024 \
    --output_dir testee/bin/royale --failure_list expected_failures.txt \
    testee/royale/run.sh
```

`RUNNER` overrides the runner executable for `just test-royale`. Compiler output
and failure reports stay under ignored `testee/bin/royale`. The build uses the
shared runtime, generated messages, and request handler directly; only the
transport and Flash compatibility classes are Royale-specific.

Verified on 2026-09-06 with Royale 0.9.12 and Node v24.13.1:

| Target | Successes | Skipped | Expected failures | Unexpected failures |
|---|---:|---:|---:|---:|
| AIR | 1404 | 4217 | 10 | 0 |
| Royale / Node | 1404 | 4217 | 10 | 0 |

Both also skip all 909 text-format suite cases. These results cover the project's
existing binary proto3 and editions-proto3 scope; they do not imply support for
JSON, text format, or proto2. The existing invalid-UTF-8 expected failures apply
to both targets, with no Royale-specific exclusions.

The first Royale run exposed a signed result from compound bitwise assignment
in `readVarint32`. Assigning the complete expression restores unsigned coercion
and fixes 28 scalar/repeated uint32 failures. The same fix passes AIR conformance.
The transport smoke tests cover multiple frames, fragmented reads, clean EOF,
and truncated headers/payloads without contaminating stdout.
