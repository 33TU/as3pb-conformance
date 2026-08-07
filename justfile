BIN_DIR := "bin"
TOOLS_DIR := "tools"
GEN_DIR := "testee/generated"

# The protobuf version is pinned by the protobuf submodule: both the
# protos fed to codegen and the conformance runner build come from that
# single checkout.
PROTOBUF_DIR := "protobuf"

ADL := env("ADL", "adl")
AMXMLC := env("AMXMLC", "amxmlc")
PROTOC := env("PROTOC", "protoc")
RUNNER := env("RUNNER", TOOLS_DIR / "conformance_test_runner")

AS3_DEBUG := env("AS3_DEBUG", "true")
AS3_INLINE := env("AS3_INLINE", "true")

default:
    @just --list

# Run the conformance suite against the AIR testee
test: build-shim build-testee
    ADL={{ ADL }} {{ RUNNER }} \
        --enforce_recommended \
        --failure_list expected_failures.txt \
        {{ BIN_DIR }}/testee-shim

# Update submodules: as3pb follows origin/main, protobuf stays at the
# recorded pin (it fixes the conformance suite version)
update-submodules:
    git submodule sync
    git submodule update --init {{ PROTOBUF_DIR }}
    git submodule update --init --remote as3pb

build-shim:
    mkdir -p {{ BIN_DIR }}
    go build -o {{ BIN_DIR }}/testee-shim ./cmd/testee-shim

# Build the as3pb generators from the submodule, in its own module context
build-generators:
    mkdir -p {{ BIN_DIR }}
    go build -C as3pb -o ../{{ BIN_DIR }}/protoc-gen-as3 ./cmd/protoc-gen-as3
    go build -C as3pb -o ../{{ BIN_DIR }}/as3-protoc ./cmd/as3-protoc

# Generate AS3 for the conformance protos into testee/generated
gen: build-generators
    rm -rf {{ GEN_DIR }}
    mkdir -p {{ GEN_DIR }}
    {{ BIN_DIR }}/as3-protoc \
        --protoc_bin={{ PROTOC }} \
        --protoc_gen_as3_bin={{ BIN_DIR }}/protoc-gen-as3 \
        --as3_out={{ GEN_DIR }} \
        -I {{ PROTOBUF_DIR }}/conformance \
        -I {{ PROTOBUF_DIR }}/src \
        {{ PROTOBUF_DIR }}/conformance/conformance.proto \
        {{ PROTOBUF_DIR }}/src/google/protobuf/test_messages_proto3.proto

build-testee:
    mkdir -p testee/bin
    {{ AMXMLC }} \
        -source-path testee/src \
        -source-path {{ GEN_DIR }} \
        -source-path as3pb/runtime/src \
        -output testee/bin/as3pb-conformance.swf \
        -compiler.strict=true \
        -compiler.inline={{ AS3_INLINE }} \
        -debug={{ AS3_DEBUG }} \
        testee/src/Main.as

# Build conformance_test_runner (and a matching protoc) from the submodule
build-runner:
    mkdir -p {{ TOOLS_DIR }}
    git -C {{ PROTOBUF_DIR }} submodule update --init --recursive --depth 1
    cmake -S {{ PROTOBUF_DIR }} -B {{ TOOLS_DIR }}/protobuf-build \
        -DCMAKE_BUILD_TYPE=Release \
        -Dprotobuf_BUILD_CONFORMANCE=ON \
        -Dprotobuf_BUILD_TESTS=OFF
    cmake --build {{ TOOLS_DIR }}/protobuf-build --target conformance_test_runner -j 8
    cp {{ TOOLS_DIR }}/protobuf-build/conformance_test_runner {{ TOOLS_DIR }}/
