package
{
	import flash.desktop.NativeApplication;
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.InvokeEvent;
	import flash.events.ProgressEvent;
	import flash.events.SecurityErrorEvent;
	import flash.events.TimerEvent;
	import flash.net.Socket;
	import flash.utils.ByteArray;
	import flash.utils.Endian;
	import flash.utils.Timer;

	import conformance.ConformanceRequest;
	import conformance.ConformanceResponse;
	import conformance.WireFormat;
	import protobuf_test_messages.proto3.TestAllTypesProto3;

	/**
	 * Conformance testee: connects back to the Go shim on the port given as
	 * the first invoke argument and answers length-prefixed (little-endian
	 * uint32) ConformanceRequest frames with ConformanceResponse frames.
	 */
	public class Main extends Sprite
	{
		private static const PROTO3_MESSAGE_TYPE:String = "protobuf_test_messages.proto3.TestAllTypesProto3";

		/**
		 * Suites finish within seconds and the runner never idles between
		 * requests, so a quiet minute means the shim is gone. The watchdog
		 * guarantees the instance dies even when the runtime (e.g. under
		 * Wine) never delivers the socket-close event.
		 */
		private static const IDLE_EXIT_MS:Number = 60000;

		private var socket:Socket;
		private var inBuffer:ByteArray = new ByteArray();
		private var outBuffer:ByteArray = new ByteArray();
		private var watchdog:Timer = new Timer(IDLE_EXIT_MS, 1);

		public function Main()
		{
			inBuffer.endian = Endian.LITTLE_ENDIAN;
			watchdog.addEventListener(TimerEvent.TIMER, onWatchdogTimeout);
			watchdog.start();
			NativeApplication.nativeApplication.addEventListener(InvokeEvent.INVOKE, onInvoke);
		}

		private function onWatchdogTimeout(event:TimerEvent):void
		{
			trace("testee: idle for " + IDLE_EXIT_MS + " ms, exiting");
			NativeApplication.nativeApplication.exit(0);
		}

		private function onInvoke(event:InvokeEvent):void
		{
			NativeApplication.nativeApplication.removeEventListener(InvokeEvent.INVOKE, onInvoke);

			if (event.arguments.length < 1)
			{
				trace("testee: missing port argument");
				NativeApplication.nativeApplication.exit(1);
				return;
			}

			socket = new Socket();
			socket.endian = Endian.LITTLE_ENDIAN;
			socket.addEventListener(ProgressEvent.SOCKET_DATA, onSocketData);
			socket.addEventListener(Event.CLOSE, onSocketClose);
			socket.addEventListener(IOErrorEvent.IO_ERROR, onSocketError);
			socket.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSocketError);
			socket.connect("127.0.0.1", int(event.arguments[0]));
		}

		private function onSocketData(event:ProgressEvent):void
		{
			watchdog.reset();
			watchdog.start();

			// Append new bytes at the tail; position stays the read cursor.
			// A single event may carry a partial frame or several frames.
			socket.readBytes(inBuffer, inBuffer.length, socket.bytesAvailable);

			while (inBuffer.length - inBuffer.position >= 4)
			{
				const frameStart:uint = inBuffer.position;
				const frameLength:uint = inBuffer.readUnsignedInt();

				if (inBuffer.length - inBuffer.position < frameLength)
				{
					inBuffer.position = frameStart;
					break;
				}

				handleFrame(inBuffer.position + frameLength);
			}

			if (inBuffer.position == inBuffer.length)
				inBuffer.clear();
		}

		private function handleFrame(end:uint):void
		{
			const response:ConformanceResponse = new ConformanceResponse();

			try
			{
				const request:ConformanceRequest = ConformanceRequest.deserializeBytes(inBuffer, null, end);
				handleRequest(request, response);
			}
			catch (e:*)
			{
				response.runtimeError = String(e);
				response.resultCase = ConformanceResponse.FIELD_RUNTIME_ERROR;
			}

			inBuffer.position = end;
			sendResponse(response);
		}

		private function handleRequest(request:ConformanceRequest, response:ConformanceResponse):void
		{
			if (request.messageType != PROTO3_MESSAGE_TYPE)
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

			var message:TestAllTypesProto3;
			try
			{
				request.protobufPayload.position = 0;
				message = TestAllTypesProto3.deserializeBytes(request.protobufPayload);
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
				TestAllTypesProto3.serializeBytes(message, response.protobufPayload);
				response.resultCase = ConformanceResponse.FIELD_PROTOBUF_PAYLOAD;
			}
			catch (e:*)
			{
				response.serializeError = String(e);
				response.resultCase = ConformanceResponse.FIELD_SERIALIZE_ERROR;
			}
		}

		private function sendResponse(response:ConformanceResponse):void
		{
			outBuffer.clear();
			ConformanceResponse.serializeBytes(response, outBuffer);

			socket.writeUnsignedInt(outBuffer.length);
			socket.writeBytes(outBuffer);
			socket.flush();
		}

		private function onSocketClose(event:Event):void
		{
			NativeApplication.nativeApplication.exit(0);
		}

		private function onSocketError(event:Event):void
		{
			trace("testee: socket error: " + event);
			NativeApplication.nativeApplication.exit(1);
		}
	}
}
