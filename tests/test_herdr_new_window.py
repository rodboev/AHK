import ctypes
import importlib.util
import os
from pathlib import Path
import threading
import time
import unittest
import uuid


@unittest.skipUnless(os.name == "nt", "Windows named pipes")
class PipeRelayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = Path(__file__).resolve().parents[1] / "herdr-new-window.py"
        spec = importlib.util.spec_from_file_location("herdr_new_window", path)
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def setUp(self):
        self.pipes = []

    def tearDown(self):
        for pipe in self.pipes:
            self.module.KERNEL.CancelIoEx(pipe.handle, None)
        for pipe in self.pipes:
            pipe.close()

    def pair(self):
        name = "herdr-relay-test-" + uuid.uuid4().hex
        server = self.module.listen(name)
        self.pipes.append(server)
        client = self.module.open_pipe(name)
        self.pipes.append(client)
        self.module.connect_pipe(server)
        return server, client

    def test_idle_read_does_not_block_opposite_write(self):
        module = self.module
        server, client = self.pair()
        received = []
        reader = threading.Thread(target=lambda: received.append(module.read_frame(server)), daemon=True)
        reader.start()
        time.sleep(0.05)
        sent = threading.Event()

        def send():
            module.write_frame(server, b"output before any input")
            sent.set()

        threading.Thread(target=send, daemon=True).start()
        completed_without_input = sent.wait(1)
        module.write_frame(client, b"input")
        reader.join(1)
        self.assertTrue(completed_without_input, "A waiting read blocked the opposite write")
        self.assertEqual(module.read_frame(client, 1), b"output before any input")
        self.assertEqual(received, [b"input"])

    def test_stream_relay_preserves_large_frames_in_both_directions(self):
        module = self.module
        left, client = self.pair()
        right, server = self.pair()
        bridge = threading.Thread(target=module.bridge, args=(left, right), daemon=True)
        bridge.start()
        payloads = [b"small", bytes(range(256)) * 1024 + b"partial chunk", b"last"]
        failures = []

        def send(pipe):
            try:
                for payload in payloads:
                    module.write_frame(pipe, payload)
            except Exception as error:
                failures.append(error)

        writers = [threading.Thread(target=send, args=(pipe,), daemon=True) for pipe in (client, server)]
        for writer in writers:
            writer.start()
        for payload in payloads:
            self.assertEqual(module.read_frame(client, 2), payload)
            self.assertEqual(module.read_frame(server, 2), payload)
        for writer in writers:
            writer.join(1)
            self.assertFalse(writer.is_alive())
        self.assertFalse(failures)
        module.KERNEL.DisconnectNamedPipe(left.handle)
        bridge.join(2)
        self.assertFalse(bridge.is_alive())

    def test_synchronous_read_reports_its_byte_count(self):
        module = self.module
        server, client = self.pair()
        module.write_frame(client, b"payload")
        time.sleep(0.05)
        buffer = ctypes.create_string_buffer(65536)
        count = module.pipe_io(server, module.KERNEL.ReadFile, buffer, len(buffer))
        self.assertEqual(count, 11)
        self.assertEqual(buffer.raw[4:11], b"payload")

    def test_relay_retries_a_zero_length_read(self):
        module = self.module
        left, client = self.pair()
        right, server = self.pair()
        real = module.pipe_io
        remaining = [2]

        def flaky(pipe, function, buffer=None, count=0, overlapped=None):
            if pipe is left and function is module.KERNEL.ReadFile and remaining[0]:
                remaining[0] -= 1
                return 0
            return real(pipe, function, buffer, count, overlapped)

        module.pipe_io = flaky
        bridge = threading.Thread(target=module.bridge, args=(left, right), daemon=True)
        try:
            bridge.start()
            module.write_frame(client, b"survived")
            self.assertEqual(module.read_frame(server, 2), b"survived")
            self.assertEqual(remaining[0], 0)
        finally:
            module.pipe_io = real
            module.KERNEL.DisconnectNamedPipe(left.handle)
            bridge.join(2)


if __name__ == "__main__":
    unittest.main()
