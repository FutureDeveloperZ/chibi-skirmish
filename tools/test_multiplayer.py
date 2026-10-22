"""Exercise real Godot WebSocket connections, capacity, and bot takeover."""
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
COMMAND = ["godot", "--headless", "--path", str(ROOT / "game")]


def main():
    with tempfile.TemporaryDirectory(prefix="chibi-network-") as temp:
        env = os.environ | {"XDG_DATA_HOME": temp + "/data",
                            "XDG_CACHE_HOME": temp + "/cache",
                            "XDG_CONFIG_HOME": temp + "/config"}
        server_log = Path(temp) / "server.log"
        clients = []
        with server_log.open("w") as output:
            server = subprocess.Popen(COMMAND + ["--", "--server"], env=env,
                                      stdout=output, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 10
            while "SERVER_READY" not in server_log.read_text():
                if server.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError(server_log.read_text())
                time.sleep(0.1)
            for index in range(6):
                clients.append(subprocess.Popen(
                    COMMAND + ["--", "--join=ws://127.0.0.1:8910", "--test-client", f"--character={index}"],
                    env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))
            deadline = time.monotonic() + 3
            while server_log.read_text().count("PLAYER_JOINED") < 6:
                if time.monotonic() > deadline:
                    raise RuntimeError("Six clients did not connect: " + server_log.read_text())
                time.sleep(0.05)
            extra = subprocess.Popen(
                COMMAND + ["--", "--join=ws://127.0.0.1:8910", "--test-client"],
                env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            clients.append(extra)
            slots = set()
            for index, client in enumerate(clients):
                output, _ = client.communicate(timeout=15)
                if index < 6:
                    assert client.returncode == 0 and "TEST_CLIENT_OK" in output, output
                    line = next(line for line in output.splitlines() if "TEST_CLIENT_OK" in line)
                    slots.add(int(line.split("slot=")[1].split()[0]))
                    assert f"character={index}" in line, line
                    print(line)
                else:
                    assert "PLAYER_ASSIGNED" not in output and client.returncode != 0, output
                    print("Seventh client rejected as expected")
            assert slots == set(range(6)), slots
            time.sleep(0.2)
            log = server_log.read_text()
            assert "bot took over" in log, log
            assert "SCRIPT ERROR" not in log and "ERROR:" not in log, log
            print("MULTIPLAYER PASS: six unique slots, synchronized state, capacity limit, bot takeover")
        finally:
            for client in clients:
                if client.poll() is None:
                    client.kill()
                    client.wait()
            server.terminate()
            server.wait(timeout=5)


if __name__ == "__main__":
    main()
