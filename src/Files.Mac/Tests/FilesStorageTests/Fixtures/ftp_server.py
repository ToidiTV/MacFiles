"""Loopback-only FTP fixture for native provider integration tests."""
import pathlib
import socket
import socketserver
import sys
import ssl

ROOT = pathlib.Path(sys.argv[1]).resolve()
TLS = None
if len(sys.argv) > 3:
    TLS = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    TLS.load_cert_chain(sys.argv[2], sys.argv[3])


class Handler(socketserver.StreamRequestHandler):
    def reply(self, text):
        self.wfile.write((text + "\r\n").encode())
        self.wfile.flush()

    def path(self, value):
        candidate = ROOT / value.lstrip("/") if value.startswith("/") else self.cwd / value
        candidate = candidate.resolve()
        if candidate != ROOT and ROOT not in candidate.parents:
            raise ValueError("Outside fixture")
        return candidate

    def handle(self):
        self.cwd = ROOT
        self.passive = None
        self.secure_data = False
        self.reply("220 MacFiles test fixture")
        try:
            while True:
                line = self.rfile.readline().decode().rstrip("\r\n")
                if not line:
                    break
                command, _, value = line.partition(" ")
                command = command.upper()
                try:
                    if command == "AUTH" and TLS is not None:
                        self.reply("234 Starting TLS")
                        self.connection = TLS.wrap_socket(self.connection, server_side=True)
                        self.rfile = self.connection.makefile("rb")
                        self.wfile = self.connection.makefile("wb")
                    elif command == "PBSZ":
                        self.reply("200 PBSZ accepted")
                    elif command == "PROT":
                        self.secure_data = value == "P"
                        self.reply("200 Protection set")
                    elif command == "USER":
                        self.reply("331 Password required")
                    elif command == "PASS":
                        self.reply("230 Logged in")
                    elif command == "PWD":
                        self.reply('257 "/' + str(self.cwd.relative_to(ROOT)).replace(".", "", 1) + '"')
                    elif command == "CWD":
                        target = self.path(value)
                        if not target.is_dir():
                            raise ValueError("Not directory")
                        self.cwd = target
                        self.reply("250 Directory changed")
                    elif command in ("TYPE", "OPTS", "NOOP"):
                        self.reply("200 OK")
                    elif command == "SYST":
                        self.reply("215 UNIX Type: L8")
                    elif command == "FEAT":
                        self.reply("211-Features\r\n MLSD\r\n UTF8\r\n211 End")
                    elif command in ("EPSV", "PASV"):
                        if self.passive:
                            self.passive.close()
                        self.passive = socket.socket()
                        self.passive.bind(("127.0.0.1", 0))
                        self.passive.listen(1)
                        self.passive.settimeout(10)
                        port = self.passive.getsockname()[1]
                        self.reply(f"229 Entering Extended Passive Mode (|||{port}|)" if command == "EPSV" else f"227 Entering Passive Mode (127,0,0,1,{port // 256},{port % 256})")
                    elif command in ("MLSD", "LIST", "NLST", "RETR", "STOR"):
                        self.reply("150 Opening data connection")
                        conn, _ = self.passive.accept()
                        if self.secure_data:
                            conn = TLS.wrap_socket(conn, server_side=True)
                        with conn:
                            if command == "STOR":
                                with self.path(value).open("wb") as output:
                                    while data := conn.recv(65536):
                                        output.write(data)
                            elif command == "RETR":
                                conn.sendall(self.path(value).read_bytes())
                            else:
                                lines = []
                                for item in sorted(self.cwd.iterdir()):
                                    if command == "MLSD":
                                        lines.append(f"type={'dir' if item.is_dir() else 'file'};size={item.stat().st_size}; {item.name}")
                                    elif command == "NLST":
                                        lines.append(item.name)
                                    else:
                                        lines.append(f"{'d' if item.is_dir() else '-'}rw-r--r-- 1 501 20 {item.stat().st_size} Oct 31 19:00 {item.name}")
                                conn.sendall(("\r\n".join(lines) + "\r\n").encode())
                        self.passive.close()
                        self.passive = None
                        self.reply("226 Transfer complete")
                    elif command == "SIZE":
                        self.reply(f"213 {self.path(value).stat().st_size}")
                    elif command == "MKD":
                        self.path(value).mkdir()
                        self.reply("257 Created")
                    elif command == "RMD":
                        self.path(value).rmdir()
                        self.reply("250 Removed")
                    elif command == "DELE":
                        self.path(value).unlink()
                        self.reply("250 Deleted")
                    elif command == "RNFR":
                        self.renaming = self.path(value)
                        self.reply("350 Ready")
                    elif command == "RNTO":
                        self.renaming.rename(self.path(value))
                        self.reply("250 Renamed")
                    elif command == "QUIT":
                        self.reply("221 Goodbye")
                        break
                    else:
                        self.reply("502 Unsupported fixture command")
                except (OSError, ValueError):
                    self.reply("550 Unavailable")
        finally:
            if self.passive:
                self.passive.close()


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True


with Server(("127.0.0.1", 0), Handler) as server:
    print(server.server_address[1], flush=True)
    server.serve_forever()
