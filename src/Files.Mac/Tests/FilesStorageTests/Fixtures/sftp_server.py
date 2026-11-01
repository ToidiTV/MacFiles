"""Disposable loopback SFTP server. Requires paramiko in the supplied test Python."""
import os
import pathlib
import socket
import sys
import threading
import time
import paramiko

ROOT = pathlib.Path(sys.argv[1]).resolve()
KEYS = pathlib.Path(sys.argv[2])
KEY = paramiko.RSAKey.generate(2048)

class Auth(paramiko.ServerInterface):
    def check_auth_password(self, username, password):
        return paramiko.AUTH_SUCCESSFUL if username == 'fixture' and password == 'fixture-password' else paramiko.AUTH_FAILED
    def get_allowed_auths(self, username):
        return 'password'
    def check_channel_request(self, kind, chanid):
        return paramiko.OPEN_SUCCEEDED if kind == 'session' else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

class Files(paramiko.SFTPServerInterface):
    def path(self, path):
        target = (ROOT / path.lstrip('/')).resolve()
        if target != ROOT and ROOT not in target.parents:
            raise PermissionError(path)
        return target
    def list_folder(self, path):
        try:
            result = []
            for child in self.path(path).iterdir():
                attr = paramiko.SFTPAttributes.from_stat(child.stat()); attr.filename = child.name; result.append(attr)
            return result
        except OSError as error: return paramiko.SFTPServer.convert_errno(error.errno)
    def stat(self, path):
        try: return paramiko.SFTPAttributes.from_stat(self.path(path).stat())
        except OSError as error: return paramiko.SFTPServer.convert_errno(error.errno)
    lstat = stat
    def open(self, path, flags, attr):
        try:
            fd = os.open(self.path(path), flags, 0o600)
            stream = os.fdopen(fd, 'r+b' if flags & os.O_RDWR else 'wb' if flags & os.O_WRONLY else 'rb')
            handle = paramiko.SFTPHandle(flags); handle.readfile = stream; handle.writefile = stream; return handle
        except OSError as error: return paramiko.SFTPServer.convert_errno(error.errno)
    def mkdir(self, path, attr):
        try: self.path(path).mkdir(); return paramiko.SFTP_OK
        except OSError as error: return paramiko.SFTPServer.convert_errno(error.errno)
    def rmdir(self, path):
        try: self.path(path).rmdir(); return paramiko.SFTP_OK
        except OSError as error: return paramiko.SFTPServer.convert_errno(error.errno)
    def remove(self, path):
        try: self.path(path).unlink(); return paramiko.SFTP_OK
        except OSError as error: return paramiko.SFTPServer.convert_errno(error.errno)
    def rename(self, old, new):
        try: self.path(old).rename(self.path(new)); return paramiko.SFTP_OK
        except OSError as error: return paramiko.SFTPServer.convert_errno(error.errno)

listener = socket.socket(); listener.bind(('127.0.0.1', 0)); listener.listen()
port = listener.getsockname()[1]
KEYS.write_text(f'[127.0.0.1]:{port} {KEY.get_name()} {KEY.get_base64()}\n')
print(port, flush=True)
def serve(client):
    transport = paramiko.Transport(client); transport.add_server_key(KEY)
    transport.set_subsystem_handler('sftp', paramiko.SFTPServer, Files)
    try:
        transport.start_server(server=Auth())
        while transport.is_active(): time.sleep(0.05)
    finally: transport.close()
while True:
    client, _ = listener.accept(); threading.Thread(target=serve, args=(client,), daemon=True).start()
