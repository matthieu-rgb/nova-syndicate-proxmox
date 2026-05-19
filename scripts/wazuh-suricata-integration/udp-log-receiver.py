#!/usr/bin/env python3
"""
T-WAZUH-SURICATA-INTEGRATION
Deploy sur app01 : /usr/local/sbin/udp-log-receiver.py
Unit systemd : /etc/systemd/system/suricata-fw-receiver.service

UDP datagram receiver -> append each datagram as a line to log file.
Tournant en User=wazuh / Group=wazuh pour que le fichier soit lisible par
wazuh-logcollector (qui ingere via <localfile> log_format=json).

Pourquoi ce script et pas nc -u -l -k ?
- nc -k (keep listening) ne fonctionne pas pour UDP : multi-datagrammes
  ne sont pas reecrits sur stdout. Un seul packet, puis EOF.
- nc -u -l (sans -k) sert UN seul datagramme et termine.
"""
import socket
import sys
import os
import signal

PORT = int(os.environ.get("RECV_PORT", "5141"))
BIND = os.environ.get("RECV_BIND", "0.0.0.0")
LOG = os.environ.get("RECV_LOG", "/var/log/suricata-fw.log")

def reopen_log():
    return open(LOG, "ab", buffering=0)

def handler(signum, frame):
    sys.stdout.write("signal received, exiting\n")
    sys.exit(0)

signal.signal(signal.SIGTERM, handler)
signal.signal(signal.SIGINT, handler)

log_fp = [reopen_log()]
def sighup(signum, frame):
    """logrotate-friendly: reopen log on SIGHUP."""
    try:
        log_fp[0].close()
    except Exception:
        pass
    log_fp[0] = reopen_log()
signal.signal(signal.SIGHUP, sighup)

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((BIND, PORT))
sys.stdout.write(f"listening on {BIND}:{PORT} -> {LOG}\n")
sys.stdout.flush()

while True:
    data, addr = s.recvfrom(65535)
    if not data:
        continue
    if not data.endswith(b"\n"):
        data = data + b"\n"
    log_fp[0].write(data)
