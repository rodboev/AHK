"""Open a new local Herdr workspace through a client-scoped pipe connection."""

import argparse
from contextlib import ExitStack, contextmanager
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import threading
import time
import traceback
import uuid


LOG_PATH = None
# An SGR mouse report, either intact or already stripped of its ESC [ prefix.
MOUSE_REPORT = re.compile(rb"\x1b\[<[0-9;]+[Mm]|<[0-9]+;[0-9]+;[0-9]+[Mm]")


def write_log(path, event, detail):
    # Append and close per line so an AHK reload can still truncate AHK_Debug.log.
    try:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write("%s | herdr-new-window | %s | pid=%d%s\n" % (time.strftime("%H:%M:%S"), event, os.getpid(), detail))
    except OSError:
        pass


def log(event, **fields):
    if LOG_PATH:
        write_log(LOG_PATH, event, "".join(" %s=%s" % item for item in fields.items()))


KERNEL = ctypes.WinDLL("kernel32", use_last_error=True)
KERNEL.CreateNamedPipeW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID]
KERNEL.CreateNamedPipeW.restype = wintypes.HANDLE
KERNEL.ConnectNamedPipe.argtypes = [wintypes.HANDLE, wintypes.LPVOID]
KERNEL.ConnectNamedPipe.restype = wintypes.BOOL
KERNEL.PeekNamedPipe.argtypes = [wintypes.HANDLE, wintypes.LPVOID, wintypes.DWORD, wintypes.LPVOID, ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
KERNEL.PeekNamedPipe.restype = wintypes.BOOL
KERNEL.ReadFile.argtypes = [wintypes.HANDLE, wintypes.LPVOID, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
KERNEL.ReadFile.restype = wintypes.BOOL
KERNEL.WriteFile.argtypes = [wintypes.HANDLE, wintypes.LPCVOID, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
KERNEL.WriteFile.restype = wintypes.BOOL
KERNEL.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
KERNEL.CreateFileW.restype = wintypes.HANDLE
KERNEL.CreateEventW.argtypes = [wintypes.LPVOID, wintypes.BOOL, wintypes.BOOL, wintypes.LPCWSTR]
KERNEL.CreateEventW.restype = wintypes.HANDLE
KERNEL.ResetEvent.argtypes = [wintypes.HANDLE]
KERNEL.ResetEvent.restype = wintypes.BOOL
KERNEL.CloseHandle.argtypes = [wintypes.HANDLE]
KERNEL.GetOverlappedResult.argtypes = [wintypes.HANDLE, wintypes.LPVOID, ctypes.POINTER(wintypes.DWORD), wintypes.BOOL]
KERNEL.GetOverlappedResult.restype = wintypes.BOOL
KERNEL.CancelIoEx.argtypes = [wintypes.HANDLE, wintypes.LPVOID]
KERNEL.CancelIoEx.restype = wintypes.BOOL
KERNEL.DisconnectNamedPipe.argtypes = [wintypes.HANDLE]
KERNEL.DisconnectNamedPipe.restype = wintypes.BOOL
KERNEL.LocalFree.argtypes = [wintypes.HLOCAL]
KERNEL.LocalFree.restype = wintypes.HLOCAL
ADVAPI = ctypes.WinDLL("advapi32", use_last_error=True)
ADVAPI.ConvertStringSecurityDescriptorToSecurityDescriptorW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, ctypes.POINTER(wintypes.LPVOID), wintypes.LPVOID]
ADVAPI.ConvertStringSecurityDescriptorToSecurityDescriptorW.restype = wintypes.BOOL
MAX_FRAME = 32 * 1024 * 1024


class SecurityAttributes(ctypes.Structure):
    _fields_ = [("length", wintypes.DWORD), ("descriptor", wintypes.LPVOID), ("inherit", wintypes.BOOL)]


class Overlapped(ctypes.Structure):
    _fields_ = [("internal", ctypes.c_size_t), ("internal_high", ctypes.c_size_t), ("offset", wintypes.DWORD), ("offset_high", wintypes.DWORD), ("event", wintypes.HANDLE)]


class Pipe:
    def __init__(self, handle, name):
        if handle == wintypes.HANDLE(-1).value:
            raise ctypes.WinError(ctypes.get_last_error())
        self.handle, self.name = handle, name

    def close(self):
        if self.handle is not None:
            KERNEL.CloseHandle(self.handle)
            self.handle = None

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


@contextmanager
def pipe_operation():
    overlapped = Overlapped()
    overlapped.event = KERNEL.CreateEventW(None, True, False, None)
    if not overlapped.event:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        yield overlapped
    finally:
        KERNEL.CloseHandle(overlapped.event)


def pipe_io(pipe, function, buffer=None, count=0, overlapped=None):
    if overlapped is None:
        with pipe_operation() as operation:
            return pipe_io(pipe, function, buffer, count, operation)
    if not KERNEL.ResetEvent(overlapped.event):
        raise ctypes.WinError(ctypes.get_last_error())
    transferred = wintypes.DWORD()
    if buffer is None:
        ok = function(pipe.handle, ctypes.byref(overlapped))
    else:
        ok = function(pipe.handle, buffer, count, ctypes.byref(transferred), ctypes.byref(overlapped))
    if not ok:
        error = ctypes.get_last_error()
        if buffer is None and error == 535:
            return 0
        if error != 997:
            raise ctypes.WinError(error)
        if not KERNEL.GetOverlappedResult(pipe.handle, ctypes.byref(overlapped), ctypes.byref(transferred), True):
            raise ctypes.WinError(ctypes.get_last_error())
    elif buffer is not None and not transferred.value:
        # An overlapped handle can complete synchronously and leave the byte count unset, which reads as EOF.
        if not KERNEL.GetOverlappedResult(pipe.handle, ctypes.byref(overlapped), ctypes.byref(transferred), True):
            raise ctypes.WinError(ctypes.get_last_error())
    return transferred.value


def connect_pipe(pipe):
    pipe_io(pipe, KERNEL.ConnectNamedPipe)


def uint(value):
    if value < 251:
        return bytes([value])
    if value <= 65535:
        return b"\xfb" + struct.pack("<H", value)
    if value <= 0xFFFFFFFF:
        return b"\xfc" + struct.pack("<I", value)
    return b"\xfd" + struct.pack("<Q", value)


def string(value):
    data = value.encode("utf-8")
    return uint(len(data)) + data


class Decoder:
    def __init__(self, data):
        self.data = data
        self.pos = 0

    def take(self, length):
        data = self.data[self.pos:self.pos + length]
        if len(data) != length:
            raise ValueError("Truncated Herdr message")
        self.pos += length
        return data

    def uint(self):
        tag = self.take(1)[0]
        if tag < 251:
            return tag
        return int.from_bytes(self.take({251: 2, 252: 4, 253: 8}[tag]), "little")

    def string(self):
        return self.take(self.uint()).decode("utf-8")


def control(kind, data):
    return uint(20) + string(kind) + string(json.dumps(data, separators=(",", ":")))


def read_exact(pipe, size, timeout=None):
    result = bytearray()
    deadline = time.monotonic() + timeout if timeout else None
    while len(result) < size:
        count = size - len(result)
        if deadline:
            available = wintypes.DWORD()
            if not KERNEL.PeekNamedPipe(pipe.handle, None, 0, None, ctypes.byref(available), None):
                raise ctypes.WinError(ctypes.get_last_error())
            if not available.value:
                if time.monotonic() >= deadline:
                    raise TimeoutError("Herdr pipe timed out")
                time.sleep(0.005)
                continue
            count = min(count, available.value)
        # Overlapped handles allow writes while the opposite relay thread waits in ReadFile.
        buffer = ctypes.create_string_buffer(count)
        transferred = pipe_io(pipe, KERNEL.ReadFile, buffer, count)
        if not transferred:
            raise EOFError("Herdr pipe closed")
        result.extend(buffer.raw[:transferred])
    return bytes(result)


def read_frame(pipe, timeout=None):
    size = struct.unpack("<I", read_exact(pipe, 4, timeout))[0]
    if not 0 < size <= MAX_FRAME:
        raise ValueError(f"Invalid Herdr frame length {size}")
    return read_exact(pipe, size, timeout)


def write_frame(pipe, payload):
    data = struct.pack("<I", len(payload)) + payload
    buffer = ctypes.create_string_buffer(data)
    offset = 0
    while offset < len(data):
        transferred = pipe_io(pipe, KERNEL.WriteFile, ctypes.byref(buffer, offset), len(data) - offset)
        if not transferred:
            raise EOFError("Herdr pipe closed during write")
        offset += transferred


def open_pipe(path):
    handle = KERNEL.CreateFileW("\\\\.\\pipe\\" + str(path), 0xC0000000, 0, None, 3, 0x40000000, None)
    return Pipe(handle, str(path))


def listen(path):
    descriptor = wintypes.LPVOID()
    if not ADVAPI.ConvertStringSecurityDescriptorToSecurityDescriptorW("D:P(A;;GA;;;SY)(A;;GA;;;OW)", 1, ctypes.byref(descriptor), None):
        raise ctypes.WinError(ctypes.get_last_error())
    attributes = SecurityAttributes(ctypes.sizeof(SecurityAttributes), descriptor, False)
    try:
        handle = KERNEL.CreateNamedPipeW("\\\\.\\pipe\\" + str(path), 3 | 0x80000 | 0x40000000, 8, 1, 65536, 65536, 0, ctypes.byref(attributes))
        error = ctypes.get_last_error()
    finally:
        KERNEL.LocalFree(descriptor)
    if handle == wintypes.HANDLE(-1).value:
        raise ctypes.WinError(error)
    return Pipe(handle, str(path))


class Endpoint:
    def __init__(self, pipe):
        self.pipe = pipe
        self.snapshot = None
        self.welcome = None

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.pipe.close()

    def reconnect(self):
        name = self.pipe.name
        self.pipe.close()
        self.__init__(open_pipe(name))
        self.connect()

    def receive(self):
        frame = read_frame(self.pipe, 10)
        decoder = Decoder(frame)
        tag = decoder.uint()
        if tag == 20:
            kind, data = decoder.string(), json.loads(decoder.string())
            if kind == "endpoint.welcome.v1":
                if data.get("error"):
                    raise RuntimeError(str(data["error"]))
                if data["generation"] != 1 or data["snapshot_codec"] != "shell.snapshot.v1":
                    raise RuntimeError("Unsupported Herdr endpoint protocol")
                self.welcome = data
            elif kind == "shell.snapshot.v1":
                self.snapshot = data
            return kind, data
        if tag == 18:
            boot, request_id = decoder.string(), decoder.string()
            final = bool(decoder.take(1)[0])
            return "response", (request_id, final, decoder.take(decoder.uint()))
        return "other", None

    def connect(self):
        hello = dict(generation=1, cell_width_px=0, cell_height_px=0, surface_size=dict(cols=80, rows=24), pixel_mouse=False, direct_graphics=False, endpoint_keybindings=False, mouse_capture=True, surface_active=False,
                     snapshot_codecs=["shell.snapshot.v1"], surface_codecs=["shell.surface.v1"], input_codecs=["shell.input.semantic.v1"], blob_codecs=["shell.blob.v1"])
        write_frame(self.pipe, control("endpoint.hello.v1", hello))
        deadline = time.monotonic() + 10
        while self.welcome is None or self.snapshot is None:
            if time.monotonic() > deadline:
                raise TimeoutError("Herdr did not send its initial snapshot")
            self.receive()

    def request(self, method, params):
        request_id = "ahk-" + uuid.uuid4().hex
        request = dict(id=request_id, method=method, params=params)
        write_frame(self.pipe, uint(15) + string(self.snapshot["boot_id"]) + string(json.dumps(request)))
        chunks = bytearray()
        deadline = time.monotonic() + 10
        while True:
            if time.monotonic() > deadline:
                raise TimeoutError(f"Herdr did not finish {method}")
            kind, data = self.receive()
            if kind == "response" and data[0] == request_id:
                chunks.extend(data[2])
                if data[1]:
                    response = json.loads(chunks)
                    if response.get("error"):
                        raise RuntimeError(str(response["error"]))
                    return response

    def resize(self, cols, rows, cell_width=0, cell_height=0, pixel_mouse=False):
        write_frame(self.pipe, uint(12) + uint(cell_width) + uint(cell_height) + uint(cols) + uint(rows) + bytes([pixel_mouse]))


def cli(exe, session, *args):
    command = [exe] + (["--session", session] if session else []) + list(args)
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", timeout=15, creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return json.loads(result.stdout)["result"] if result.stdout.strip() else {}


def wait_focused_pane(exe, session, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            panes = cli(exe, session, "pane", "list").get("panes", [])
        except Exception:
            panes = []
        for entry in panes:
            if entry.get("focused"):
                return entry["pane_id"]
        time.sleep(0.25)
    return None


def cold_start(args, alacritty, exe):
    # With no server there is no other window to protect from the resize, so no proxy is needed.
    env = {key: value for key, value in os.environ.items() if not key.startswith("HERDR_")}
    command = [alacritty, "--working-directory", args.cwd]
    if args.session:
        command += ["--command", "herdr.exe", "--session", args.session]
    subprocess.Popen(command, env=env)
    if not args.command:
        return
    pane = wait_focused_pane(exe, args.session)
    if not pane:
        log("cold-start-no-pane", session=args.session)
        return
    cli(exe, args.session, "pane", "run", pane, args.command)
    log("cold-start", session=args.session, pane=pane)


def prepare(endpoint, exe, session, cwd):
    endpoint.connect()
    required = {"workspace.focus", "client_shell.surface.set"}
    if not required.issubset(endpoint.welcome["methods"]):
        raise RuntimeError("Herdr does not advertise the required endpoint commands")
    created = cli(exe, session, "workspace", "create", "--cwd", cwd, "--no-focus")
    workspace = created["workspace"]["workspace_id"]
    pane = created["root_pane"]["pane_id"]
    for attempt in range(4):
        snapshot = cli(exe, session, "api", "snapshot")["snapshot"]
        tab = endpoint.snapshot["focused_tab_id"]
        if tab is None or snapshot["focused_tab_id"] == tab:
            break
        endpoint.reconnect()
    else:
        raise RuntimeError(f"Workspace focus changed during preparation. Workspace {workspace} is available; press F10 again.")
    layout = next((layout for layout in snapshot["layouts"] if layout["tab_id"] == tab), None)
    if layout is None and tab is not None:
        raise RuntimeError("Cannot preserve the existing workspace dimensions")
    area = layout["area"] if layout else dict(width=80, height=24)
    # Activation claims geometry before client-scoped navigation, so retain the old tab's exact size.
    endpoint.resize(area["width"], area["height"])
    endpoint.request("client_shell.surface.set", dict(active=True))
    endpoint.request("workspace.focus", dict(workspace_id=workspace))
    deadline = time.monotonic() + 10
    while endpoint.snapshot["focused_workspace_id"] != workspace:
        if time.monotonic() > deadline:
            raise TimeoutError(f"Herdr did not select workspace {workspace}")
        endpoint.receive()
    log("prepared", workspace=workspace, pane=pane, previous_tab=tab, size="%sx%s" % (area["width"], area["height"]))
    return workspace, pane


def trace_mouse(label, data, count, seen):
    # Mouse reports arriving as literal text mean their ESC [ prefix was lost. Log both forms to find where.
    if not LOG_PATH or seen[0] >= 40:
        return
    match = MOUSE_REPORT.search(data, 0, count)
    if not match:
        return
    seen[0] += 1
    start = max(0, match.start() - 8)
    log("mouse-bytes", dir=label, n=count, at=match.start(), bytes=repr(data[start:match.end() + 4]).replace(" ", ""))


def relay(source, destination, stopped, label=""):
    try:
        buffer = ctypes.create_string_buffer(65536)
        empty = 0
        seen = [0]
        with pipe_operation() as read_operation, pipe_operation() as write_operation:
            while not stopped.is_set():
                count = pipe_io(source, KERNEL.ReadFile, buffer, len(buffer), read_operation)
                if not count:
                    # A closed peer surfaces as ERROR_BROKEN_PIPE, so retry a bare zero before tearing the window down.
                    empty += 1
                    if empty > 3:
                        raise EOFError("client disconnected")
                    time.sleep(0.005)
                    continue
                empty = 0
                trace_mouse(label, buffer.raw, count, seen)
                offset = 0
                while offset < count and not stopped.is_set():
                    written = pipe_io(destination, KERNEL.WriteFile, ctypes.byref(buffer, offset), count - offset, write_operation)
                    if not written:
                        raise EOFError("client disconnected during write")
                    offset += written
    except (OSError, EOFError, ValueError) as error:
        log("relay-stopped", error='"%s"' % error)
    finally:
        stopped.set()


def bridge(upstream, downstream, on_ready=None):
    stopped = threading.Event()
    directions = [(upstream, downstream, "from-server"), (downstream, upstream, "from-terminal")]
    workers = [threading.Thread(target=relay, args=(source, destination, stopped, label), daemon=True) for source, destination, label in directions]
    for worker in workers:
        worker.start()
    try:
        if on_ready:
            on_ready()
        stopped.wait()
    finally:
        stopped.set()
        deadline = time.monotonic() + 2
        while any(worker.is_alive() for worker in workers):
            KERNEL.CancelIoEx(upstream.handle, None)
            KERNEL.CancelIoEx(downstream.handle, None)
            for worker in workers:
                worker.join(0.05)
            if time.monotonic() > deadline:
                log("relay-cancel-failed")
                os._exit(1)


def main():
    global LOG_PATH
    parser = argparse.ArgumentParser()
    parser.add_argument("--cwd", required=True)
    parser.add_argument("--command", default="")
    parser.add_argument("--session", default="")
    parser.add_argument("--log", default="")
    args = parser.parse_args()
    LOG_PATH = args.log or None
    with ExitStack() as resources:
        launch(args, resources)


def launch(args, resources):
    exe, alacritty = shutil.which("herdr.exe"), shutil.which("alacritty.exe")
    if not exe or not alacritty:
        raise RuntimeError("Herdr and Alacritty must be on PATH")
    directory = Path(os.environ["APPDATA"]) / "herdr"
    if args.session:
        directory = directory / "sessions" / args.session
    proxy_path = Path(tempfile.gettempdir()) / ("herdr-ahk-" + uuid.uuid4().hex + ".sock")
    try:
        endpoint = resources.enter_context(Endpoint(open_pipe(directory / "herdr-client.sock")))
    except OSError as error:
        # Only a missing pipe means no server. Anything else (denied, busy) may have live windows to protect.
        if error.winerror not in (2, 3):
            raise RuntimeError("Herdr's socket is present but unusable: %s" % error)
        log("no-server", session=args.session, error='"%s"' % error)
        cold_start(args, alacritty, exe)
        return
    workspace, pane = prepare(endpoint, exe, args.session, args.cwd)
    upstream = endpoint.pipe
    downstream = resources.enter_context(listen(proxy_path))
    # Only this Alacritty child inherits the pipe override; pane processes keep the server's environment.
    env = {key: value for key, value in os.environ.items() if not key.startswith("HERDR_")}
    env["HERDR_CLIENT_SOCKET_PATH"] = str(proxy_path)
    if args.session:
        env["HERDR_SESSION"] = args.session
    window = subprocess.Popen([alacritty, "--working-directory", args.cwd], env=env)
    def watch_window():
        window.wait()
        log("alacritty-exited", workspace=workspace)
        os._exit(0)
    threading.Thread(target=watch_window, daemon=True).start()
    connected = threading.Event()
    def watchdog():
        if not connected.wait(20):
            log("attach-timeout", workspace=workspace, seconds=20)
            os._exit(1)
    threading.Thread(target=watchdog, daemon=True).start()
    connect_pipe(downstream)
    decoder = Decoder(read_frame(downstream, 10))
    if decoder.uint() != 20 or decoder.string() != "endpoint.hello.v1":
        raise RuntimeError("Unexpected Herdr client handshake")
    hello = json.loads(decoder.string())
    if hello["generation"] != 1 or hello["direct_graphics"] or hello["endpoint_keybindings"]:
        raise RuntimeError("Unsupported Herdr client capabilities")
    size = hello["surface_size"]
    endpoint.resize(size["cols"], size["rows"], hello["cell_width_px"], hello["cell_height_px"], hello["pixel_mouse"])
    write_frame(upstream, uint(19) + bytes([hello["mouse_capture"]]))
    write_frame(downstream, control("endpoint.welcome.v1", endpoint.welcome))
    write_frame(downstream, control("shell.snapshot.v1", endpoint.snapshot))
    connected.set()
    log("attached", workspace=workspace, size="%sx%s" % (size["cols"], size["rows"]))
    run_command = (lambda: cli(exe, args.session, "pane", "run", pane, args.command)) if args.command else None
    try:
        bridge(upstream, downstream, run_command)
    finally:
        upstream.close()
        KERNEL.DisconnectNamedPipe(downstream.handle)
    # Herdr may retain remote connections while its Local endpoint reconnects.
    while True:
        connect_pipe(downstream)
        try:
            with open_pipe(directory / "herdr-client.sock") as replacement:
                log("local-reconnect", workspace=workspace)
                bridge(replacement, downstream)
        except OSError as error:
            log("local-reconnect-failed", error='"%s"' % error)
        finally:
            KERNEL.DisconnectNamedPipe(downstream.handle)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # A crash is written whatever the toggle says, since the message box points the user at the log.
        write_log(LOG_PATH or Path(tempfile.gettempdir()) / "AHK_Debug.log", "launch-failed", ' error="%s"' % " / ".join(traceback.format_exc().split("\n")))
        ctypes.windll.user32.MessageBoxW(None, "Could not open the new Herdr workspace. See %TEMP%\\AHK_Debug.log.", "Herdr", 16)
        raise
