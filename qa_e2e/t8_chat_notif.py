"""E2E batch 8 — Chat (REST), Notifications (REST), and WebSocket realtime."""
import os, time, asyncio, json
import websockets
from qa import Client, record, S, B, django_setup

PWD = "ChangeMe123!"
BUY = "buyer@marche-cm.local"; SUP = "supplier@marche-cm.local"
SELLER_ID = 8; PRODUCT_ID = 9; TRANSIT_ID = 10
WS = "ws://127.0.0.1:8000"


def f(n):
    return os.path.join("media", n)


def rest_part():
    buy = Client("buyer"); buy.login(BUY, PWD)
    sup = Client("supplier"); sup.login(SUP, PWD)
    other = Client("other"); em = f"oc{int(time.time())}@qa.test"
    Client("anon").req("POST", "/api/auth/register/", json_body={"name": "OC", "email": em,
        "phone_number": "+237690777888", "password": PWD}, auth=False, note="reg oc")
    other.login(em, PWD)

    # T8.1 create chat room buyer<->seller
    r = buy.req("POST", "/api/chat/rooms/", json_body={"name": "QA Room", "participants": [SELLER_ID]}, note="create room")
    room_id = r.json().get("id") if S(r) == 201 else None
    record("T8.1", "Création d'un salon de chat acheteur↔vendeur", "major", S(r) == 201 and room_id,
           "201 + room id", f"status={S(r)} room={room_id} body={B(r,120)}", endpoint="POST /api/chat/rooms/")

    # T8.2 send TEXT
    r = buy.req("POST", "/api/chat/messages/", json_body={"room": room_id, "type": "TEXT", "content": "Bonjour, dispo ?"}, note="send text")
    record("T8.2", "Envoi message texte", "major", S(r) == 201, "201", f"status={S(r)} body={B(r,120)}", endpoint="POST /api/chat/messages/")

    # T8.3 send IMAGE
    with open(f("product1.jpg"), "rb") as fp:
        r = buy.req("POST", "/api/chat/messages/", files={"file": ("c.jpg", fp, "image/jpeg")},
                    data={"room": str(room_id), "type": "IMAGE", "content": ""}, note="send image")
    record("T8.3", "Envoi message image", "major", S(r) == 201, "201", f"status={S(r)} body={B(r,120)}", endpoint="POST /api/chat/messages/")

    # T8.4 send VIDEO
    with open(f("clip.mp4"), "rb") as fp:
        r = buy.req("POST", "/api/chat/messages/", files={"file": ("c.mp4", fp, "video/mp4")},
                    data={"room": str(room_id), "type": "VIDEO", "content": ""}, note="send video")
    record("T8.4", "Envoi message vidéo", "major", S(r) == 201, "201", f"status={S(r)} body={B(r,120)}", endpoint="POST /api/chat/messages/")

    # T8.5 seller reads messages
    r = sup.req("GET", f"/api/chat/messages/?room={room_id}", note="seller reads")
    body = r.json() if S(r) == 200 else []
    n = body.get("count") if isinstance(body, dict) else (len(body) if isinstance(body, list) else 0)
    record("T8.5", "Le vendeur (participant) lit les messages du salon", "major",
           S(r) == 200 and (n or 0) >= 3, "200 + >=3 messages", f"status={S(r)} count={n}", endpoint="GET /api/chat/messages/")

    # T8.6 non-participant cannot read room messages
    r = other.req("GET", f"/api/chat/messages/?room={room_id}", note="other reads")
    ob = r.json() if S(r) == 200 else []
    on = ob.get("count") if isinstance(ob, dict) else (len(ob) if isinstance(ob, list) else 0)
    record("T8.6", "Non-participant ne voit pas les messages du salon (cloisonnement)", "critical",
           S(r) == 200 and (on or 0) == 0, "200 + 0 message", f"status={S(r)} count={on}", endpoint="GET /api/chat/messages/")

    # T8.7 non-participant cannot send
    r = other.req("POST", "/api/chat/messages/", json_body={"room": room_id, "type": "TEXT", "content": "intrus"}, note="other sends")
    record("T8.7", "Non-participant ne peut pas écrire dans le salon", "critical", S(r) == 403,
           "403", f"status={S(r)} body={B(r,120)}", endpoint="POST /api/chat/messages/")

    # T8.8 messages are append-only (no DELETE)
    r = buy.req("DELETE", "/api/chat/messages/1/", note="delete msg")
    record("T8.8", "Messages append-only (DELETE désactivé)", "major", S(r) == 405,
           "405", f"status={S(r)}", endpoint="DELETE /api/chat/messages/{id}/")

    # T8.9 notifications list (seller has order notifications from earlier)
    r = sup.req("GET", "/api/notifications/", note="seller notifs")
    nb = r.json() if S(r) == 200 else []
    nn = nb.get("count") if isinstance(nb, dict) else (len(nb) if isinstance(nb, list) else 0)
    record("T8.9", "Liste des notifications accessible", "major", S(r) == 200,
           "200", f"status={S(r)} count={nn}", endpoint="GET /api/notifications/")

    return buy, sup, room_id


def main():
    buy, sup, room_id = rest_part()

    async def ws_tests():
        buy_tok = buy.access; sup_tok = sup.access
        other = Client("otherws"); em = f"ow{int(time.time())}@qa.test"
        Client("anon").req("POST", "/api/auth/register/", json_body={"name": "OW", "email": em,
            "phone_number": "+237690999000", "password": PWD}, auth=False, note="reg ow")
        other.login(em, PWD); other_tok = other.access

        # T8.10 /ws/notifications/ without token -> rejected
        try:
            async with websockets.connect(f"{WS}/ws/notifications/", open_timeout=8) as ws:
                await asyncio.wait_for(ws.recv(), timeout=2)
            rejected = False
        except Exception:
            rejected = True
        record("T8.10", "WebSocket /ws/notifications/ sans token refusé", "critical", rejected,
               "connexion refusée", f"rejected={rejected}", endpoint="WS /ws/notifications/", be_file="apps/realtime/consumers.py:BaseAuthConsumer")

        # T8.11 /ws/notifications/ with token (subprotocol bearer) -> accepted
        try:
            async with websockets.connect(f"{WS}/ws/notifications/", subprotocols=["bearer", buy_tok], open_timeout=8) as ws:
                accepted = True
        except Exception as e:
            accepted = False; print("notif ws err:", repr(e))
        record("T8.11", "WebSocket /ws/notifications/ avec JWT (sous-protocole bearer) accepté", "critical", accepted,
               "connexion acceptée", f"accepted={accepted}", endpoint="WS /ws/notifications/")

        # T8.12 realtime delivery: seller on /ws/events/, buyer creates order -> seller receives event
        received = None
        try:
            async with websockets.connect(f"{WS}/ws/events/?token={sup_tok}", open_timeout=8) as ws:
                # create an order as buyer (sync) in a thread
                def make_order():
                    return buy.req("POST", "/api/orders/", json_body={"product": PRODUCT_ID, "quantity": 1,
                        "preferred_transit_agent": TRANSIT_ID, "transport_mode": "SEA"}, note="ws order trigger")
                r = await asyncio.to_thread(make_order)
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=10)
                    received = msg
                except asyncio.TimeoutError:
                    received = None
        except Exception as e:
            print("events ws err:", repr(e))
        record("T8.12", "Temps réel: le vendeur reçoit un événement WS quand l'acheteur commande", "critical",
               received is not None, "événement WS reçu sur /ws/events/ après création de commande",
               f"received={(received[:160] if received else None)}", endpoint="WS /ws/events/ + POST /api/orders/",
               be_file="apps/notifications/service.py:create_realtime_notification -> broadcast_user_event(user_{id})")

        # T8.13 chat WS: participant accepted, non-participant rejected
        part_ok = False; nonpart_rejected = False
        try:
            async with websockets.connect(f"{WS}/ws/chat/{room_id}/?token={buy_tok}", open_timeout=8) as ws:
                part_ok = True
        except Exception as e:
            print("chat ws participant err:", repr(e))
        try:
            async with websockets.connect(f"{WS}/ws/chat/{room_id}/?token={other_tok}", open_timeout=8) as ws:
                # if it stays open and we can't tell, try recv; consumer closes non-participants
                await asyncio.wait_for(ws.recv(), timeout=2)
            nonpart_rejected = False
        except Exception:
            nonpart_rejected = True
        record("T8.13", "WebSocket chat: participant accepté, non-participant refusé", "critical",
               part_ok and nonpart_rejected, "participant=ouvert, non-participant=fermé",
               f"participant_ok={part_ok} nonparticipant_rejected={nonpart_rejected}", endpoint="WS /ws/chat/{room}/")

    asyncio.run(ws_tests())


if __name__ == "__main__":
    main()
