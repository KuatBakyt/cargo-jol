from pathlib import Path

from django.db import IntegrityError, transaction
from django.db.models import Count, Q
from django.http import FileResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from drf_spectacular.utils import extend_schema
from rest_framework import generics, serializers, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from .filters import CargoFilter
from .models import (
    Cargo,
    Company,
    Conversation,
    FavoriteCargo,
    Message,
    Notification,
    Offer,
    Order,
    Vehicle,
)
from .serializers import (
    CargoSerializer,
    CompanySerializer,
    ConversationSerializer,
    FavoriteSerializer,
    LoginSerializer,
    MessageSerializer,
    NotificationSerializer,
    OfferCreateSerializer,
    OfferSerializer,
    OfferUpdateSerializer,
    OrderSerializer,
    RegisterSerializer,
    ReviewSerializer,
    StatusSerializer,
    UserSerializer,
    VehicleSerializer,
)
from .services import (
    accept_offer,
    change_offer,
    change_order_status,
    create_offer,
    match_score,
    notify,
    notify_matches,
    require_role,
)


class RegisterView(generics.CreateAPIView):
    permission_classes = [AllowAny]
    serializer_class = RegisterSerializer
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth"


class LoginView(TokenObtainPairView):
    serializer_class = LoginSerializer
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth"


class RefreshView(TokenRefreshView):
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth"


class MeView(generics.RetrieveUpdateAPIView):
    serializer_class = UserSerializer
    http_method_names = ["get", "patch", "head", "options"]

    def get_object(self):
        return self.request.user


class CompanyViewSet(viewsets.ModelViewSet):
    serializer_class = CompanySerializer
    http_method_names = ["get", "post", "patch", "head", "options"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Company.objects.none()
        return Company.objects.filter(owner=self.request.user)

    def perform_create(self, serializer):
        if Company.objects.filter(owner=self.request.user).exists():
            raise ValidationError("One company per user is allowed.")
        serializer.save(owner=self.request.user)

    def perform_update(self, serializer):
        # Editing a verified identity always requires a new review.
        serializer.save(verification_status=Company.Verification.UNVERIFIED)

    @action(detail=True, methods=["post"], url_path="request-verification")
    def request_verification(self, request, pk=None):
        company = self.get_object()
        if company.verification_status not in ["unverified", "rejected"]:
            raise ValidationError("Company is already verified or awaiting review.")
        company.verification_status = Company.Verification.PENDING
        company.save(update_fields=["verification_status", "updated_at"])
        return Response(self.get_serializer(company).data)


class VehicleViewSet(viewsets.ModelViewSet):
    serializer_class = VehicleSerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Vehicle.objects.none()
        return Vehicle.objects.filter(owner=self.request.user).order_by("-created_at")

    def perform_create(self, serializer):
        require_role(self.request.user, "carrier")
        serializer.save(owner=self.request.user)

    def perform_update(self, serializer):
        with transaction.atomic():
            vehicle = Vehicle.objects.select_for_update().get(pk=serializer.instance.pk)
            if vehicle.orders.exclude(status__in=["completed", "cancelled"]).exists():
                raise ValidationError("An active-order vehicle cannot be modified.")
            serializer.instance = vehicle
            serializer.save()

    def perform_destroy(self, instance):
        with transaction.atomic():
            vehicle = Vehicle.objects.select_for_update().get(pk=instance.pk)
            if vehicle.offers.exists() or vehicle.orders.exists():
                raise ValidationError("Vehicle has offers/orders; set it inactive instead.")
            vehicle.delete()


class MatchQuerySerializer(serializers.Serializer):
    vehicle_id = serializers.IntegerField(min_value=1, required=False)
    match_date = serializers.DateField(required=False)


class CargoViewSet(viewsets.ModelViewSet):
    serializer_class = CargoSerializer
    filterset_class = CargoFilter
    ordering_fields = ["created_at", "price", "loading_date"]
    ordering = ["-created_at", "-id"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Cargo.objects.none()
        user = self.request.user
        queryset = Cargo.objects.select_related("owner").annotate(offers_count=Count("offers"))
        if self.request.query_params.get("mine") == "true":
            return queryset.filter(owner=user)
        return queryset.filter(
            Q(owner=user) | Q(status="active") | Q(order__carrier=user)
        ).distinct()

    def get_serializer_context(self):
        context = super().get_serializer_context()
        query = MatchQuerySerializer(data=self.request.query_params)
        query.is_valid(raise_exception=True)
        if "vehicle_id" in query.validated_data:
            context["vehicle"] = get_object_or_404(
                Vehicle, pk=query.validated_data["vehicle_id"], owner=self.request.user
            )
        context["destination"] = self.request.query_params.get("to")
        date = query.validated_data.get("match_date")
        context["loading_date"] = date.isoformat() if date else None
        return context

    def list(self, request, *args, **kwargs):
        if request.query_params.get("ordering") != "relevance":
            return super().list(request, *args, **kwargs)
        queryset = self.filter_queryset(self.get_queryset())
        context = self.get_serializer_context()
        items = sorted(
            queryset,
            key=lambda cargo: match_score(
                cargo,
                context.get("vehicle"),
                context.get("destination"),
                context.get("loading_date"),
            ),
            reverse=True,
        )
        page = self.paginate_queryset(items)
        return self.get_paginated_response(self.get_serializer(page, many=True).data)

    def perform_create(self, serializer):
        require_role(self.request.user, "shipper")
        with transaction.atomic():
            cargo = serializer.save(owner=self.request.user)
            if cargo.status == "active":
                notify_matches(cargo)

    def perform_update(self, serializer):
        with transaction.atomic():
            cargo = Cargo.objects.select_for_update().get(pk=serializer.instance.pk)
            if cargo.owner_id != self.request.user.id:
                raise PermissionDenied("Only owner can modify cargo.")
            if cargo.status not in ["draft", "active"]:
                raise ValidationError("Cargo is locked after assignment/cancellation.")
            pending = cargo.offers.filter(status="pending")
            if pending.exists() and serializer.validated_data.get("status") != "cancelled":
                raise ValidationError("Cancel pending offers before modifying cargo conditions.")
            previous_status = cargo.status
            serializer.instance = cargo
            cargo = serializer.save()
            if cargo.status == "cancelled":
                for offer in pending:
                    notify(offer.carrier, "offer_rejected", "Груз отменён", offer.id)
                pending.update(status="rejected")
            elif previous_status == "draft" and cargo.status == "active":
                notify_matches(cargo)

    def perform_destroy(self, instance):
        with transaction.atomic():
            cargo = Cargo.objects.select_for_update().get(pk=instance.pk)
            if cargo.owner_id != self.request.user.id:
                raise PermissionDenied("Only owner can delete cargo.")
            if cargo.status != "draft" or cargo.offers.exists():
                raise ValidationError("Only unused drafts can be deleted; cancel published cargo.")
            cargo.delete()

    @extend_schema(request=OfferCreateSerializer, responses={201: OfferSerializer})
    @action(detail=True, methods=["get", "post"])
    def offers(self, request, pk=None):
        cargo = self.get_object()
        if request.method == "POST":
            serializer = OfferCreateSerializer(data=request.data)
            serializer.is_valid(raise_exception=True)
            offer = create_offer(request.user, cargo.id, serializer.validated_data)
            return Response(OfferSerializer(offer).data, status=status.HTTP_201_CREATED)
        offers = cargo.offers.select_related("carrier")
        if cargo.owner_id != request.user.id:
            offers = offers.filter(carrier=request.user)
        page = self.paginate_queryset(offers)
        return self.get_paginated_response(OfferSerializer(page, many=True).data)

    @action(detail=True, methods=["post", "delete"])
    def favorite(self, request, pk=None):
        cargo = self.get_object()
        if request.method == "DELETE":
            FavoriteCargo.objects.filter(user=request.user, cargo=cargo).delete()
            return Response(status=status.HTTP_204_NO_CONTENT)
        FavoriteCargo.objects.get_or_create(user=request.user, cargo=cargo)
        return Response({"cargo": cargo.id}, status=status.HTTP_201_CREATED)


class OfferViewSet(viewsets.GenericViewSet):
    serializer_class = OfferSerializer
    queryset = Offer.objects.all()

    @extend_schema(request=OfferUpdateSerializer, responses=OfferSerializer)
    def partial_update(self, request, pk=None):
        offer = get_object_or_404(Offer, pk=pk)
        serializer = OfferUpdateSerializer(offer, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        updated = change_offer(request.user, offer.id, serializer.validated_data)
        return Response(OfferSerializer(updated).data)

    @extend_schema(request=None, responses=OrderSerializer)
    @action(detail=True, methods=["post"])
    def accept(self, request, pk=None):
        offer = get_object_or_404(Offer, pk=pk)
        order = accept_offer(request.user, offer.id)
        return Response(OrderSerializer(order).data, status=status.HTTP_201_CREATED)

    @extend_schema(request=None, responses=OfferSerializer)
    @action(detail=True, methods=["post"])
    def reject(self, request, pk=None):
        offer = get_object_or_404(Offer, pk=pk)
        return Response(OfferSerializer(change_offer(request.user, offer.id, action="reject")).data)


class OrderViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = OrderSerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Order.objects.none()
        return Order.objects.filter(
            Q(shipper=self.request.user) | Q(carrier=self.request.user)
        ).select_related("shipper", "carrier", "conversation")

    @extend_schema(request=StatusSerializer, responses=OrderSerializer)
    @action(detail=True, methods=["patch"], url_path="status")
    def update_status(self, request, pk=None):
        order = self.get_object()
        serializer = StatusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        order = change_order_status(request.user, order.id, serializer.validated_data["status"])
        return Response(OrderSerializer(order).data)

    @action(detail=True, methods=["get"])
    def conversation(self, request, pk=None):
        return Response(ConversationSerializer(self.get_object().conversation).data)

    @extend_schema(request=ReviewSerializer, responses={201: ReviewSerializer})
    @action(detail=True, methods=["get", "post"])
    def reviews(self, request, pk=None):
        order = self.get_object()
        if request.method == "GET":
            return Response(ReviewSerializer(order.reviews.all(), many=True).data)
        if order.status != "completed":
            raise ValidationError("Only completed orders can be reviewed.")
        if order.reviews.filter(author=request.user).exists():
            raise ValidationError("You already reviewed this order.")
        serializer = ReviewSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        target = order.carrier if request.user.id == order.shipper_id else order.shipper
        try:
            with transaction.atomic():
                review = serializer.save(order=order, author=request.user, target_user=target)
        except IntegrityError as exc:
            raise ValidationError("You already reviewed this order.") from exc
        return Response(ReviewSerializer(review).data, status=status.HTTP_201_CREATED)


class ConversationViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = ConversationSerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Conversation.objects.none()
        return Conversation.objects.filter(
            Q(order__shipper=self.request.user) | Q(order__carrier=self.request.user)
        )

    @extend_schema(request=MessageSerializer, responses={201: MessageSerializer})
    @action(detail=True, methods=["get", "post"])
    def messages(self, request, pk=None):
        conversation = self.get_object()
        if request.method == "POST":
            serializer = MessageSerializer(data=request.data, context={"request": request})
            serializer.is_valid(raise_exception=True)
            with transaction.atomic():
                message = serializer.save(conversation=conversation, sender=request.user)
                order = conversation.order
                recipient = order.carrier if order.shipper_id == request.user.id else order.shipper
                notify(recipient, "new_message", "Новое сообщение", conversation.id)
            return Response(
                MessageSerializer(message, context={"request": request}).data,
                status=status.HTTP_201_CREATED,
            )
        messages = conversation.messages.select_related("sender")
        page = self.paginate_queryset(messages)
        return self.get_paginated_response(
            MessageSerializer(page, many=True, context={"request": request}).data
        )

    @action(detail=True, methods=["post"], url_path="read")
    def mark_read(self, request, pk=None):
        count = (
            self.get_object()
            .messages.exclude(sender=request.user)
            .filter(read_at__isnull=True)
            .update(read_at=timezone.now())
        )
        return Response({"updated": count})


class MessageFileView(generics.GenericAPIView):
    serializer_class = MessageSerializer

    def get(self, request, pk):
        message = get_object_or_404(
            Message.objects.filter(
                Q(conversation__order__shipper=request.user)
                | Q(conversation__order__carrier=request.user)
            ),
            pk=pk,
        )
        if not message.attachment:
            return Response({"detail": "No attachment."}, status=404)
        return FileResponse(
            message.attachment.open("rb"),
            as_attachment=True,
            filename=f"message-{message.id}{Path(message.attachment.name).suffix}",
        )


class FavoriteViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = FavoriteSerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return FavoriteCargo.objects.none()
        visible = Cargo.objects.filter(
            Q(owner=self.request.user) | Q(status="active") | Q(order__carrier=self.request.user)
        )
        return (
            FavoriteCargo.objects.filter(user=self.request.user, cargo__in=visible)
            .select_related("cargo", "cargo__owner")
            .order_by("-created_at")
        )


class NotificationViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = NotificationSerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Notification.objects.none()
        return Notification.objects.filter(user=self.request.user)

    @action(detail=True, methods=["post"], url_path="read")
    def mark_read(self, request, pk=None):
        notification = self.get_object()
        notification.is_read = True
        notification.save(update_fields=["is_read"])
        return Response(self.get_serializer(notification).data)

    @action(detail=False, methods=["post"], url_path="read-all")
    def read_all(self, request):
        return Response({"updated": self.get_queryset().filter(is_read=False).update(is_read=True)})


class AvatarView(generics.GenericAPIView):
    serializer_class = UserSerializer

    def put(self, request):
        from .serializers import AvatarSerializer

        serializer = AvatarSerializer(request.user, data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response({"avatar_url": "/api/auth/avatar"})

    def get(self, request):
        if not request.user.avatar:
            return Response({"detail": "No avatar."}, status=404)
        return FileResponse(
            request.user.avatar.open("rb"),
            as_attachment=True,
            filename="avatar" + Path(request.user.avatar.name).suffix,
        )
