package
{
    import conformance.ConformanceRequest;
    import conformance.ConformanceResponse;
    import conformance.WireFormat;
    import protobuf_test_messages.proto3.TestAllTypesProto3;
    import protobuf_test_messages.editions.proto3.TestAllTypesProto3;

    /** Shared request handling for the AIR and Royale transports. */
    public final class ConformanceCodec
    {
        private static const PROTO3_MESSAGE_TYPE:String = "protobuf_test_messages.proto3.TestAllTypesProto3";
        private static const EDITIONS_PROTO3_MESSAGE_TYPE:String = "protobuf_test_messages.editions.proto3.TestAllTypesProto3";

        public static function handleRequest(request:ConformanceRequest, response:ConformanceResponse):void
        {
            if (request.messageType != PROTO3_MESSAGE_TYPE && request.messageType != EDITIONS_PROTO3_MESSAGE_TYPE)
            {
                response.skipped = "unsupported message type: " + request.messageType;
                response.resultCase = ConformanceResponse.FIELD_SKIPPED;
                return;
            }

            if (request.payloadCase != ConformanceRequest.FIELD_PROTOBUF_PAYLOAD)
            {
                response.skipped = "only protobuf input is supported";
                response.resultCase = ConformanceResponse.FIELD_SKIPPED;
                return;
            }

            if (request.requestedOutputFormat != WireFormat.PROTOBUF)
            {
                response.skipped = "only protobuf output is supported";
                response.resultCase = ConformanceResponse.FIELD_SKIPPED;
                return;
            }

            if (request.messageType == PROTO3_MESSAGE_TYPE)
                roundtripProto3(request, response);
            else
                roundtripEditionsProto3(request, response);
        }

        private static function roundtripProto3(request:ConformanceRequest, response:ConformanceResponse):void
        {
            var message:protobuf_test_messages.proto3.TestAllTypesProto3;
            try
            {
                request.protobufPayload.position = 0;
                message = protobuf_test_messages.proto3.TestAllTypesProto3.deserializeBytes(request.protobufPayload);
            }
            catch (e:*)
            {
                response.parseError = String(e);
                response.resultCase = ConformanceResponse.FIELD_PARSE_ERROR;
                return;
            }

            try
            {
                response.protobufPayload.length = 0;
                protobuf_test_messages.proto3.TestAllTypesProto3.serializeBytes(message, response.protobufPayload);
                response.resultCase = ConformanceResponse.FIELD_PROTOBUF_PAYLOAD;
            }
            catch (e:*)
            {
                response.serializeError = String(e);
                response.resultCase = ConformanceResponse.FIELD_SERIALIZE_ERROR;
            }
        }

        private static function roundtripEditionsProto3(request:ConformanceRequest, response:ConformanceResponse):void
        {
            var message:protobuf_test_messages.editions.proto3.TestAllTypesProto3;
            try
            {
                request.protobufPayload.position = 0;
                message = protobuf_test_messages.editions.proto3.TestAllTypesProto3.deserializeBytes(request.protobufPayload);
            }
            catch (e:*)
            {
                response.parseError = String(e);
                response.resultCase = ConformanceResponse.FIELD_PARSE_ERROR;
                return;
            }

            try
            {
                response.protobufPayload.length = 0;
                protobuf_test_messages.editions.proto3.TestAllTypesProto3.serializeBytes(message, response.protobufPayload);
                response.resultCase = ConformanceResponse.FIELD_PROTOBUF_PAYLOAD;
            }
            catch (e:*)
            {
                response.serializeError = String(e);
                response.resultCase = ConformanceResponse.FIELD_SERIALIZE_ERROR;
            }
        }

    }
}
