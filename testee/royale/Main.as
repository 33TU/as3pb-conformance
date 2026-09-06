package
{
    import flash.utils.ByteArray;
    import flash.utils.Endian;
    import conformance.ConformanceRequest;
    import conformance.ConformanceResponse;

    /** Synchronous binary stdio transport for the protobuf conformance runner. */
    public final class Main
    {
        private const fs:Object = require("fs");

        public function Main()
        {
            const header:Uint8Array = new Uint8Array(4);
            const view:DataView = new DataView(header.buffer);
            while (readFully(header, true))
            {
                const input:ByteArray = new ByteArray();
                input.endian = Endian.LITTLE_ENDIAN;
                input.length = view.getUint32(0, true);
                readFully(new Uint8Array(input.data, 0, input.length), false);

                const response:ConformanceResponse = new ConformanceResponse();
                try
                {
                    const request:ConformanceRequest = ConformanceRequest.deserializeBytes(input);
                    ConformanceCodec.handleRequest(request, response);
                }
                catch (error:*)
                {
                    response.runtimeError = String(error);
                    response.resultCase = ConformanceResponse.FIELD_RUNTIME_ERROR;
                }

                const output:ByteArray = new ByteArray();
                output.endian = Endian.LITTLE_ENDIAN;
                ConformanceResponse.serializeBytes(response, output);
                view.setUint32(0, output.length, true);
                writeFully(header);
                writeFully(new Uint8Array(output.data, 0, output.length));
            }
        }

        private function readFully(bytes:Uint8Array, allowEOF:Boolean):Boolean
        {
            var offset:uint = 0;
            while (offset < bytes.length)
            {
                const count:uint = fs.readSync(0, bytes, offset, bytes.length - offset, null);
                if (!count)
                {
                    if (allowEOF && !offset)
                        return false;
                    throw new Error("Truncated conformance frame");
                }
                offset += count;
            }
            return true;
        }

        private function writeFully(bytes:Uint8Array):void
        {
            var offset:uint = 0;
            while (offset < bytes.length)
            {
                const count:uint = fs.writeSync(1, bytes, offset, bytes.length - offset);
                if (!count)
                    throw new Error("Unable to write conformance response");
                offset += count;
            }
        }
    }
}
