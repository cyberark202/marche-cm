import re
from decimal import Decimal, InvalidOperation

from django.db import transaction
from django.db.models import Avg, Count, Q
from rest_framework import permissions, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response

from apps.accounts.models import UserRole
from apps.accounts.security import write_audit_log
from apps.chat.models import ChatRoom, DeliveryState, Message, MessageReceipt, MessageType
from apps.notifications.realtime import broadcast_event
from apps.orders.models import OrderReview
from .models import BuyerPreferenceProfile, BuyerProductInteraction, Product, ProductFavorite, SavedProductFilter, VideoComment, VideoLike
from .serializers import (
    ProductFavoriteSerializer,
    ProductSerializer,
    SavedProductFilterSerializer,
    TrackProductViewSerializer,
    VideoCommentSerializer,
)


class ProductViewSet(viewsets.ModelViewSet):
    queryset = Product.objects.select_related("category", "seller").prefetch_related("seller__compliance_documents").all()
    serializer_class = ProductSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_permissions(self):
        if self.action in {"list", "retrieve", "image_search"}:
            return [permissions.AllowAny()]
        return [permission() for permission in self.permission_classes]

    def get_queryset(self):
        queryset = self.queryset
        if self.action in {"list", "retrieve", "image_search"}:
            queryset = queryset.filter(is_active=True)
        search_query = (self.request.query_params.get("q") or "").strip().lower()
        if search_query:
            terms = [term for term in re.split(r"\s+", search_query) if term]
            for term in terms:
                queryset = queryset.filter(
                    Q(title__icontains=term) | Q(brand__icontains=term) | Q(description__icontains=term)
                )
        return queryset

    def perform_create(self, serializer):
        if self.request.user.role not in {UserRole.SUPPLIER, UserRole.WHOLESALER}:
            raise PermissionDenied("Seuls fournisseur et grossiste peuvent publier.")
        product = serializer.save(seller=self.request.user)
        broadcast_event(
            "products",
            "created",
            {"id": product.id, "title": product.title, "seller_id": product.seller_id},
        )

    def perform_update(self, serializer):
        if not (self.request.user.is_superuser or self.request.user.role == UserRole.GENERAL_ADMIN):
            if serializer.instance.seller_id != self.request.user.id:
                raise PermissionDenied("Modification reservee au vendeur proprietaire.")
        serializer.save()

    def perform_destroy(self, instance):
        if not (self.request.user.is_superuser or self.request.user.role == UserRole.GENERAL_ADMIN):
            if instance.seller_id != self.request.user.id:
                raise PermissionDenied("Suppression reservee au vendeur proprietaire.")
        instance.delete()

    @action(detail=False, methods=["get"], url_path="mine")
    def mine(self, request):
        products = self.queryset.filter(seller=request.user)
        serializer = self.get_serializer(products, many=True)
        return Response(serializer.data)

    @action(
        detail=False,
        methods=["post"],
        url_path="publish-video",
        parser_classes=[MultiPartParser, FormParser],
    )
    def publish_video(self, request):
        if request.user.role not in {UserRole.SUPPLIER, UserRole.WHOLESALER}:
            raise PermissionDenied("Seuls fournisseur et grossiste peuvent publier.")

        video_file = request.FILES.get("video")
        description = (request.data.get("description") or "").strip()
        tags = (request.data.get("tags") or "").strip()
        raw_weight_kg = str(request.data.get("weight_kg") or "").strip()
        if not video_file:
            return Response({"detail": "La video est obligatoire."}, status=status.HTTP_400_BAD_REQUEST)
        if not description:
            return Response({"detail": "La description est obligatoire."}, status=status.HTTP_400_BAD_REQUEST)
        if not tags:
            return Response({"detail": "Les tags sont obligatoires."}, status=status.HTTP_400_BAD_REQUEST)
        if not raw_weight_kg:
            return Response(
                {"detail": "Le poids du produit (en Kg) est obligatoire."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            weight_kg = Decimal(raw_weight_kg)
        except (InvalidOperation, TypeError):
            return Response(
                {"detail": "Le poids du produit (en Kg) est invalide."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if weight_kg <= 0:
            return Response(
                {"detail": "Le poids du produit (en Kg) doit etre superieur a 0."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        tag_list = [tag.strip() for tag in tags.split(",") if tag.strip()]
        category_name = tag_list[0] if tag_list else "Video"
        payload = {
            "title": f"Video produit - {category_name}",
            "brand": "Annonce",
            "description": description,
            "category_name": category_name,
            "weight_kg": str(weight_kg),
            "video": video_file,
            "tags": tags,
            "is_active": True,
        }
        if request.user.role == UserRole.SUPPLIER:
            payload.update(
                {
                    "min_order_qty": 1,
                    "max_order_qty": 1,
                    "price_for_min_qty": "0.00",
                    "price_for_max_qty": "0.00",
                    "allows_group_campaign": False,
                }
            )
        else:
            payload.update(
                {
                    "available_qty": 1,
                    "unit_price": "0.00",
                    "allows_group_campaign": True,
                }
            )

        serializer = self.get_serializer(data=payload)
        serializer.is_valid(raise_exception=True)
        product = serializer.save(seller=request.user)
        broadcast_event(
            "products",
            "video_created",
            {"id": product.id, "title": product.title, "seller_id": product.seller_id},
        )
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], url_path="contact-seller")
    def contact_seller(self, request, pk=None):
        if request.user.role != UserRole.BUYER:
            return Response(
                {"detail": "Seuls les acheteurs peuvent contacter un fournisseur depuis une publication."},
                status=status.HTTP_403_FORBIDDEN,
            )

        product = self.get_object()
        if not product.is_active:
            return Response({"detail": "Cette publication n'est plus disponible."}, status=status.HTTP_400_BAD_REQUEST)
        if product.seller_id == request.user.id:
            return Response(
                {"detail": "Vous ne pouvez pas vous contacter vous-meme."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        room = (
            ChatRoom.objects.filter(participants=request.user)
            .filter(participants=product.seller)
            .annotate(participant_count=Count("participants", distinct=True))
            .filter(participant_count=2)
            .first()
        )
        room_created = False
        if room is None:
            room = ChatRoom.objects.create(name=f"Interet produit #{product.reference_code or product.id}")
            room.participants.add(request.user, product.seller)
            room_created = True
            broadcast_event("chat", "room_created", {"id": room.id, "name": room.name})

        product_ref = product.reference_code or f"PRD-{product.id}"
        seller_ref = product.seller.reference_code or f"USR-{product.seller_id}"
        image_url = request.build_absolute_uri(product.image.url) if product.image else ""
        content = (
            f"Bonjour, je marque mon interet pour votre produit "
            f"\"{product.title}\" (ref {product_ref}). "
            f"Reference fournisseur: {seller_ref}."
        )
        if image_url:
            content = f"{content} Photo produit: {image_url}"
        message_type = MessageType.IMAGE if product.image else MessageType.TEXT
        message = Message.objects.create(
            room=room,
            sender=request.user,
            type=message_type,
            content=content,
        )
        if product.image:
            message.file.name = product.image.name
            message.save(update_fields=["file"])

        MessageReceipt.objects.update_or_create(
            message=message,
            user=product.seller,
            defaults={"state": DeliveryState.SENT},
        )
        write_audit_log(
            actor=request.user,
            action="Interet produit envoye au fournisseur",
            action_key="chat.send",
            metadata={
                "product_id": product.id,
                "product_reference": product_ref,
                "seller_id": product.seller_id,
                "room_id": room.id,
                "message_id": message.id,
            },
        )
        broadcast_event(
            "chat",
            "message_created",
            {
                "id": message.id,
                "room": room.id,
                "sender": request.user.id,
                "type": message.type,
            },
        )
        return Response(
            {
                "detail": "Message d'interet envoye au fournisseur.",
                "room_id": room.id,
                "message_id": message.id,
                "room_created": room_created,
            },
            status=status.HTTP_200_OK,
        )

    @action(detail=False, methods=["post"], url_path="track-view")
    def track_view(self, request):
        serializer = TrackProductViewSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        product_id = serializer.validated_data["product_id"]

        try:
            product = Product.objects.select_related("seller").get(pk=product_id, is_active=True)
        except Product.DoesNotExist:
            return Response({"detail": "Produit introuvable."}, status=status.HTTP_404_NOT_FOUND)

        tokens = self._tokenize_text(f"{product.title} {product.brand}")
        locality = (product.seller.country_code or "").upper()
        avg_price = (Decimal(product.price_for_min_qty) + Decimal(product.price_for_max_qty)) / Decimal("2")

        with transaction.atomic():
            profile, _ = BuyerPreferenceProfile.objects.select_for_update().get_or_create(user=request.user)
            interaction, _ = BuyerProductInteraction.objects.select_for_update().get_or_create(
                user=request.user, product=product
            )
            interaction.view_count += 1
            interaction.save(update_fields=["view_count", "last_viewed_at"])

            keyword_weights = dict(profile.keyword_weights or {})
            for token in tokens:
                keyword_weights[token] = int(keyword_weights.get(token, 0)) + 1
            locality_weights = dict(profile.locality_weights or {})
            if locality:
                locality_weights[locality] = int(locality_weights.get(locality, 0)) + 1
            profile.keyword_weights = keyword_weights
            profile.locality_weights = locality_weights
            profile.preferred_price_sum = Decimal(profile.preferred_price_sum) + avg_price
            profile.preferred_price_count += 1
            profile.save(
                update_fields=[
                    "keyword_weights",
                    "locality_weights",
                    "preferred_price_sum",
                    "preferred_price_count",
                    "updated_at",
                ]
            )

        return Response({"status": "ok"})

    @action(detail=False, methods=["get"], url_path="recommended")
    def recommended(self, request):
        products = list(self.queryset.filter(is_active=True))
        profile = BuyerPreferenceProfile.objects.filter(user=request.user).first()

        interactions = {
            item["product_id"]: item["view_count"]
            for item in BuyerProductInteraction.objects.filter(user=request.user).values("product_id", "view_count")
        }
        keyword_weights = dict(profile.keyword_weights if profile else {})
        locality_weights = dict(profile.locality_weights if profile else {})
        preferred_price_count = profile.preferred_price_count if profile else 0
        preferred_price_avg = (
            Decimal(profile.preferred_price_sum) / Decimal(preferred_price_count)
            if profile and preferred_price_count > 0
            else None
        )

        q = (request.query_params.get("q") or "").strip()
        if q:
            q_tokens = self._tokenize_text(q)
            if q_tokens:
                products = [
                    p
                    for p in products
                    if any(token in self._tokenize_text(f"{p.title} {p.brand} {p.description}") for token in q_tokens)
                ]

        def score(product):
            value = 0.0
            value += interactions.get(product.id, 0) * 6
            p_tokens = self._tokenize_text(f"{product.title} {product.brand}")
            value += sum(float(keyword_weights.get(token, 0)) * 0.8 for token in p_tokens)
            locality = (product.seller.country_code or "").upper()
            value += float(locality_weights.get(locality, 0)) * 3

            if preferred_price_avg is not None:
                mid_price = (Decimal(product.price_for_min_qty) + Decimal(product.price_for_max_qty)) / Decimal("2")
                spread = preferred_price_avg * Decimal("0.45")
                if spread <= 0:
                    spread = Decimal("1")
                distance = abs(mid_price - preferred_price_avg) / spread
                if distance > 1:
                    distance = Decimal("1")
                value += float((Decimal("1") - distance) * Decimal("5"))

            value += float(product.seller.trust_score) * 0.25
            return value

        products.sort(key=score, reverse=True)
        serializer = self.get_serializer(products, many=True)
        return Response(serializer.data)

    @action(detail=False, methods=["get"], url_path="image-search")
    def image_search(self, request):
        q = (request.query_params.get("q") or "").strip()
        if not q:
            return Response([], status=status.HTTP_200_OK)
        products = self.queryset.filter(is_active=True)
        terms = self._tokenize_text(q)
        if terms:
            products = [
                product
                for product in products
                if any(
                    token in self._tokenize_text(f"{product.title} {product.brand} {product.description}")
                    for token in terms
                )
            ]
        serializer = self.get_serializer(products, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=["get"], url_path="reviews")
    def reviews(self, request, pk=None):
        product = self.get_object()
        rows = OrderReview.objects.filter(product=product).select_related("buyer").order_by("-created_at")[:50]
        avg_rating = rows.aggregate(value=Avg("rating"))["value"] if rows else None
        payload = {
            "product_id": product.id,
            "reviews_count": len(rows),
            "average_rating": float(avg_rating) if avg_rating is not None else 0,
            "reviews": [
                {
                    "id": row.id,
                    "buyer_id": row.buyer_id,
                    "buyer_username": row.buyer.username,
                    "rating": row.rating,
                    "comment": row.comment,
                    "is_verified_purchase": row.is_verified_purchase,
                    "created_at": row.created_at.isoformat(),
                }
                for row in rows
            ],
        }
        return Response(payload, status=status.HTTP_200_OK)

    def _tokenize_text(self, raw):
        blocked = {
            "de",
            "du",
            "la",
            "le",
            "les",
            "des",
            "pour",
            "avec",
            "sans",
            "sur",
            "the",
            "and",
            "pack",
            "pcs",
            "kg",
            "ml",
            "l",
        }
        tokens = set()
        for match in re.finditer(r"[a-zA-Z0-9]{3,}", (raw or "").lower()):
            token = match.group(0)
            if token not in blocked:
                tokens.add(token)
        return tokens


class ProductFavoriteViewSet(viewsets.ModelViewSet):
    serializer_class = ProductFavoriteSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = ProductFavorite.objects.select_related("product", "user").all()

    def get_queryset(self):
        if self.request.user.is_superuser or self.request.user.role == UserRole.GENERAL_ADMIN:
            return self.queryset
        return self.queryset.filter(user=self.request.user)

    def perform_create(self, serializer):
        product = serializer.validated_data["product"]
        if not product.is_active:
            raise PermissionDenied("Seuls les produits actifs peuvent etre ajoutes aux favoris.")
        serializer.save(user=self.request.user)

    @action(detail=False, methods=["post"], url_path="toggle")
    def toggle(self, request):
        product_id = request.data.get("product_id")
        try:
            product = Product.objects.get(id=int(product_id), is_active=True)
        except (TypeError, ValueError, Product.DoesNotExist):
            return Response({"detail": "Produit introuvable."}, status=status.HTTP_404_NOT_FOUND)
        favorite = ProductFavorite.objects.filter(user=request.user, product=product).first()
        if favorite:
            favorite.delete()
            return Response({"favorited": False}, status=status.HTTP_200_OK)
        ProductFavorite.objects.create(user=request.user, product=product)
        return Response({"favorited": True}, status=status.HTTP_200_OK)


class SavedProductFilterViewSet(viewsets.ModelViewSet):
    serializer_class = SavedProductFilterSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = SavedProductFilter.objects.select_related("user").all()

    def get_queryset(self):
        if self.request.user.is_superuser or self.request.user.role == UserRole.GENERAL_ADMIN:
            return self.queryset
        return self.queryset.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)


class VideoLikeViewSet(viewsets.ViewSet):
    permission_classes = [permissions.IsAuthenticated]

    @action(detail=False, methods=["post"], url_path="toggle")
    def toggle(self, request):
        product_id = request.data.get("product_id")
        try:
            product = Product.objects.get(id=int(product_id), is_active=True)
        except (TypeError, ValueError, Product.DoesNotExist):
            return Response({"detail": "Produit introuvable."}, status=status.HTTP_404_NOT_FOUND)
        like = VideoLike.objects.filter(user=request.user, product=product).first()
        if like:
            like.delete()
            liked = False
        else:
            VideoLike.objects.create(user=request.user, product=product)
            liked = True
        total = VideoLike.objects.filter(product=product).count()
        return Response({"liked": liked, "total_likes": total}, status=status.HTTP_200_OK)

    def list(self, request):
        product_id = request.query_params.get("product_id")
        if not product_id:
            return Response({"detail": "product_id requis."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            product = Product.objects.get(id=int(product_id), is_active=True)
        except (TypeError, ValueError, Product.DoesNotExist):
            return Response({"detail": "Produit introuvable."}, status=status.HTTP_404_NOT_FOUND)
        total = VideoLike.objects.filter(product=product).count()
        liked = VideoLike.objects.filter(user=request.user, product=product).exists()
        return Response({"liked": liked, "total_likes": total}, status=status.HTTP_200_OK)


class VideoCommentViewSet(viewsets.ModelViewSet):
    serializer_class = VideoCommentSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = VideoComment.objects.select_related("user", "product").all()
    http_method_names = ["get", "post", "delete", "head", "options"]

    def get_queryset(self):
        queryset = self.queryset
        product_id = self.request.query_params.get("product_id")
        if product_id:
            queryset = queryset.filter(product_id=product_id)
        return queryset

    def perform_create(self, serializer):
        product_id = self.request.data.get("product")
        try:
            product = Product.objects.get(id=int(product_id), is_active=True)
        except (TypeError, ValueError, Product.DoesNotExist):
            raise PermissionDenied("Produit introuvable.")
        serializer.save(user=self.request.user, product=product)

    def perform_destroy(self, instance):
        if instance.user_id != self.request.user.id and not (
            self.request.user.is_superuser or self.request.user.role == "GENERAL_ADMIN"
        ):
            raise PermissionDenied("Suppression reservee a l'auteur du commentaire.")
        instance.delete()
