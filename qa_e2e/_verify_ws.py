"""Verify WebSocket realtime the way a real browser does it: send an Origin
header (AllowedHostsOriginValidator) + authenticate via the 'bearer' subprotocol
(prod disables query-string token auth). Classifies whether T8.11-8.13 failures
are pure test-harness artifacts."""
import asyncio
import os
import sys
import json
import websockets

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("QA_BASE", "http://127.0.0.1:8000")
from qa import Client

BASE = os.environ.get("QA_BASE", "http://127.0.0.1:8000")
if "digital-get" in BASE:
    WS = "wss://cm.digital-get.com"
    ORIGIN = "https://cm.digital-get.com"
else:
    WS = "ws://127.0.0.1:8000"
    ORIGIN = "http://127.0.0.1:8000"
PWD = "ChangeMe123!"


async def main():
    buy = Client("buy"); buy.login("buyer@marche-cm.local", PWD)
    sup = Client("sup"); sup.login("supplier@marche-cm.local", PWD)
    print("buyer token:", bool(buy.access), "supplier token:", bool(sup.access))

    # create a chat room buyer<->supplier (supplier id = 5)
    r = buy.req("POST", "/api/chat/rooms/", json_body={"name": "WS verify", "participants": [5]}, note="room")
    room_id = r.json().get("id") if r is not None and r.status_code == 201 else None
    print("room_id:", room_id, "status:", (r.status_code if r else None))

    # 1) /ws/notifications/ with Origin + subprotocol bearer
    try:
        async with websockets.connect(f"{WS}/ws/notifications/", subprotocols=["bearer", buy.access],
                                       origin=ORIGIN, open_timeout=10) as ws:
            print("NOTIF WS: CONNECTED (subprotocol+origin) OK")
    except Exception as e:
        print("NOTIF WS: FAIL", repr(e))

    # 2) same but WITHOUT origin (to prove the origin is what was blocking)
    try:
        async with websockets.connect(f"{WS}/ws/notifications/", subprotocols=["bearer", buy.access],
                                       open_timeout=10) as ws:
            print("NOTIF WS no-origin: CONNECTED (unexpected)")
    except Exception as e:
        print("NOTIF WS no-origin: rejected ->", type(e).__name__)

    # 3) /ws/chat/{room}/ participant with Origin + subprotocol
    if room_id:
        try:
            async with websockets.connect(f"{WS}/ws/chat/{room_id}/", subprotocols=["bearer", buy.access],
                                           origin=ORIGIN, open_timeout=10) as ws:
                print("CHAT WS participant: CONNECTED OK")
        except Exception as e:
            print("CHAT WS participant: FAIL", repr(e))

    # 4) realtime delivery: supplier listens on /ws/notifications/, buyer sends a chat message -> supplier should get an event
    if room_id:
        try:
            async with websockets.connect(f"{WS}/ws/notifications/", subprotocols=["bearer", sup.access],
                                           origin=ORIGIN, open_timeout=10) as ws:
                def send_msg():
                    return buy.req("POST", "/api/chat/messages/",
                                   json_body={"room": room_id, "type": "TEXT", "content": "ws realtime ping"},
                                   note="ws msg")
                rr = await asyncio.to_thread(send_msg)
                print("sent message status:", (rr.status_code if rr else None))
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=12)
                    print("SUPPLIER RECEIVED WS EVENT:", str(msg)[:200])
                except asyncio.TimeoutError:
                    print("SUPPLIER WS: no event within 12s")
        except Exception as e:
            print("REALTIME WS: FAIL", repr(e))


asyncio.run(main())
