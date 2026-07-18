"""Tests du chat.

* Redaction des liens (anti-désintermédiation) : fonction pure + serializer.
* Parcours WhatsApp : ticks agrégés côté expéditeur, ordre anté-chronologique,
  liste de conversations (dernier message / non-lus / interlocuteur),
  marquage lu en masse par salon, réactions emoji.
"""
from django.contrib.auth import get_user_model
from django.test import SimpleTestCase, TestCase, override_settings
from rest_framework.test import APIClient

from apps.accounts import field_crypto
from core.text_sanitize import redact_links
from apps.chat.models import ChatRoom, DeliveryState, Message, MessageReaction, MessageReceipt
from apps.chat.serializers import MessageSerializer


class RedactLinksTests(SimpleTestCase):
    def test_scheme_urls_and_shorteners_are_redacted(self):
        for raw in (
            "rejoins https://wa.me/237690000000",
            "clique hxxp://evil.tk/login",
            "http://exemple.com/promo",
            "t.me/mon_canal et bit.ly/x",
        ):
            self.assertNotIn("http", redact_links(raw).lower())
            self.assertIn("[lien retiré]", redact_links(raw))

    def test_www_and_bare_domains_are_redacted(self):
        self.assertEqual(redact_links("va sur www.exemple.cm"), "va sur [lien retiré]")
        self.assertEqual(redact_links("boutique instagram.com/shop"), "boutique [lien retiré]")

    def test_dot_obfuscation_is_redacted(self):
        self.assertIn("[lien retiré]", redact_links("exemple [.] com"))
        self.assertIn("[lien retiré]", redact_links("exemple(dot)net"))

    def test_emails_are_redacted_as_contact(self):
        self.assertEqual(
            redact_links("ecris a jean.dupont@gmail.com"),
            "ecris a [contact retiré]",
        )

    def test_legitimate_text_is_untouched(self):
        # Montants FCFA, noms de produits et libellés courants : aucun faux positif.
        for raw in (
            "200 bidons a 85.000 FCFA, total 2.320.000",
            "Node.js dernier modele",
            "Douala -> Yaounde, ETA 5 jours",
            "point de vente du quartier",
        ):
            self.assertEqual(redact_links(raw), raw)

    def test_non_string_inputs_pass_through(self):
        self.assertIsNone(redact_links(None))
        self.assertEqual(redact_links(""), "")

    def test_phone_redaction_is_opt_in(self):
        raw = "appelle le +237 677 00 00 00 ou 699112233"
        # OFF par défaut : numéros conservés (ambigu avec les montants).
        self.assertIn("677", redact_links(raw))
        # ON : numéros masqués (international + bloc 9 chiffres CM).
        cleaned = redact_links(raw, redact_phones=True)
        self.assertNotIn("677", cleaned)
        self.assertNotIn("699112233", cleaned)

    def test_phone_redaction_preserves_fcfa_amounts(self):
        # Montants avec séparateurs : jamais masqués, même quand phones=ON.
        self.assertEqual(
            redact_links("total 2 320 000 et 85.000 FCFA", redact_phones=True),
            "total 2 320 000 et 85.000 FCFA",
        )


class ChatContentRedactionTests(SimpleTestCase):
    def test_validate_content_redacts_links(self):
        cleaned = MessageSerializer().validate_content(
            "Appelle-moi, whatsapp: wa.me/237699112233"
        )
        self.assertNotIn("wa.me", cleaned)
        self.assertIn("[lien retiré]", cleaned)


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class ChatWhatsAppFlowTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        User = get_user_model()
        self.buyer = User.objects.create_user(
            username="chat_buyer", email="chat_buyer@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=1, country_code="CM",
            phone_number="+237690000901")
        self.seller = User.objects.create_user(
            username="chat_seller", email="chat_seller@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CM",
            phone_number="+237690000902")
        self.outsider = User.objects.create_user(
            username="chat_out", email="chat_out@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=1, country_code="CM",
            phone_number="+237690000903")
        self.room = ChatRoom.objects.create(name="Achat mangues")
        self.room.participants.add(self.buyer, self.seller)
        self.buyer_client = APIClient()
        self.buyer_client.force_authenticate(user=self.buyer)
        self.seller_client = APIClient()
        self.seller_client.force_authenticate(user=self.seller)

    def _send(self, client, content="bonjour"):
        response = client.post(
            "/api/chat/messages/", {"room": self.room.id, "content": content, "type": "TEXT"}
        )
        self.assertEqual(response.status_code, 201, response.content)
        return response.data

    def test_sender_ticks_progress_sent_delivered_read(self):
        message = self._send(self.buyer_client)
        # À l'envoi : 1 tick (SENT) — avant correctif, my_state était toujours ''.
        listed = self.buyer_client.get(f"/api/chat/messages/?room={self.room.id}").data["results"]
        self.assertEqual(listed[0]["my_state"], DeliveryState.SENT)

        self.seller_client.post(f"/api/chat/messages/{message['id']}/mark_delivered/", {})
        listed = self.buyer_client.get(f"/api/chat/messages/?room={self.room.id}").data["results"]
        self.assertEqual(listed[0]["my_state"], DeliveryState.DELIVERED)

        self.seller_client.post(f"/api/chat/messages/{message['id']}/mark_read/", {})
        listed = self.buyer_client.get(f"/api/chat/messages/?room={self.room.id}").data["results"]
        self.assertEqual(listed[0]["my_state"], DeliveryState.READ)

    def test_page_one_returns_most_recent_messages(self):
        for i in range(25):
            Message.objects.create(room=self.room, sender=self.buyer, content=f"msg {i}")
        response = self.buyer_client.get(f"/api/chat/messages/?room={self.room.id}")
        results = response.data["results"]
        self.assertEqual(len(results), 20)
        # Page 1 = les plus récents, ordre anté-chronologique.
        self.assertEqual(results[0]["content"], "msg 24")
        self.assertEqual(results[19]["content"], "msg 5")

    def test_room_list_exposes_last_message_unread_and_peer(self):
        self._send(self.seller_client, "premier")
        self._send(self.seller_client, "dernier message du vendeur")
        rooms = self.buyer_client.get("/api/chat/rooms/").data
        rows = rooms["results"] if isinstance(rooms, dict) else rooms
        room = next(r for r in rows if r["id"] == self.room.id)
        self.assertEqual(room["unread_count"], 2)
        self.assertEqual(room["last_message"]["snippet"], "dernier message du vendeur")
        self.assertEqual(room["peer"]["id"], self.seller.id)
        self.assertIn("is_online", room["peer"])

    def test_room_mark_read_bulk(self):
        self._send(self.seller_client, "a")
        self._send(self.seller_client, "b")
        response = self.buyer_client.post(f"/api/chat/rooms/{self.room.id}/mark_read/", {})
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.data["updated"], 2)
        states = MessageReceipt.objects.filter(user=self.buyer).values_list("state", flat=True)
        self.assertEqual(set(states), {DeliveryState.READ})
        rooms = self.buyer_client.get("/api/chat/rooms/").data
        rows = rooms["results"] if isinstance(rooms, dict) else rooms
        room = next(r for r in rows if r["id"] == self.room.id)
        self.assertEqual(room["unread_count"], 0)

    def test_react_set_replace_and_remove(self):
        message = self._send(self.buyer_client)
        url = f"/api/chat/messages/{message['id']}/react/"

        response = self.seller_client.post(url, {"emoji": "❤️"})
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.data["reactions"][0]["emoji"], "❤️")

        # Un autre emoji REMPLACE (une seule réaction par utilisateur).
        response = self.seller_client.post(url, {"emoji": "👍"})
        self.assertEqual([r["emoji"] for r in response.data["reactions"]], ["👍"])
        self.assertEqual(MessageReaction.objects.count(), 1)

        # Le même emoji RETIRE (toggle).
        response = self.seller_client.post(url, {"emoji": "👍"})
        self.assertEqual(response.data["reactions"], [])
        self.assertEqual(MessageReaction.objects.count(), 0)

    def test_react_rejected_for_non_participant(self):
        message = self._send(self.buyer_client)
        outsider_client = APIClient()
        outsider_client.force_authenticate(user=self.outsider)
        response = outsider_client.post(f"/api/chat/messages/{message['id']}/react/", {"emoji": "👍"})
        self.assertEqual(response.status_code, 404)

    def test_reactions_serialized_on_messages(self):
        message = self._send(self.buyer_client)
        self.seller_client.post(f"/api/chat/messages/{message['id']}/react/", {"emoji": "😂"})
        listed = self.buyer_client.get(f"/api/chat/messages/?room={self.room.id}").data["results"]
        self.assertEqual(listed[0]["reactions"], [{"emoji": "😂", "count": 1, "mine": False}])

    def test_rooms_sorted_by_last_activity(self):
        older = ChatRoom.objects.create(name="Ancienne")
        older.participants.add(self.buyer, self.seller)
        self._send(self.buyer_client)  # active self.room
        self.buyer_client.post(
            "/api/chat/messages/", {"room": older.id, "content": "réveil", "type": "TEXT"}
        )
        rooms = self.buyer_client.get("/api/chat/rooms/").data
        rows = rooms["results"] if isinstance(rooms, dict) else rooms
        self.assertEqual(rows[0]["id"], older.id)
