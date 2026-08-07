module github.com/33TU/as3pb-conformance

go 1.26.5

replace github.com/33TU/as3pb => ./as3pb

tool (
	github.com/33TU/as3pb/cmd/as3-protoc
	github.com/33TU/as3pb/cmd/protoc-gen-as3
)

require (
	github.com/33TU/as3pb v0.0.0-00010101000000-000000000000 // indirect
	google.golang.org/protobuf v1.36.11 // indirect
)
