from pathlib import Path

from django.contrib.auth.password_validation import validate_password
from django.db.models import Avg, Q
from django.utils import timezone
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from .models import (
    Cargo,
    Company,
    Conversation,
    FavoriteCargo,
    Message,
    Notification,
    Offer,
    Order,
    Review,
    User,
    Vehicle,
)
from .services import match_score


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = [
            "id",
            "first_name",
            "last_name",
            "phone",
            "email",
            "role",
            "is_phone_verified",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "role", "is_phone_verified", "created_at", "updated_at"]

    def validate_email(self, value):
        value = value.lower()
        if User.objects.filter(email__iexact=value).exclude(pk=self.instance.pk).exists():
            raise serializers.ValidationError("Email already registered.")
        return value

    def update(self, instance, validated_data):
        if "phone" in validated_data and validated_data["phone"] != instance.phone:
            instance.is_phone_verified = False
        return super().update(instance, validated_data)


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)

    class Meta:
        model = User
        fields = ["id", "first_name", "last_name", "email", "phone", "role", "password"]
        read_only_fields = ["id"]

    def validate_email(self, value):
        value = value.lower()
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError("Email already registered.")
        return value

    def validate(self, attrs):
        validate_password(
            attrs["password"], User(**{k: v for k, v in attrs.items() if k != "password"})
        )
        return attrs

    def create(self, validated_data):
        return User.objects.create_user(**validated_data)


class LoginSerializer(TokenObtainPairSerializer):
    def validate(self, attrs):
        attrs["email"] = attrs["email"].lower()
        return super().validate(attrs)


class PublicUserSerializer(serializers.ModelSerializer):
    rating = serializers.SerializerMethodField()
    is_company_verified = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ["id", "first_name", "last_name", "role", "rating", "is_company_verified"]

    @extend_schema_field(serializers.FloatField())
    def get_rating(self, obj):
        return obj.received_reviews.aggregate(value=Avg("rating"))["value"] or 0

    @extend_schema_field(serializers.BooleanField())
    def get_is_company_verified(self, obj):
        return Company.objects.filter(owner=obj, verification_status="verified").exists()


class CompanySerializer(serializers.ModelSerializer):
    rating = serializers.SerializerMethodField()
    completed_orders = serializers.SerializerMethodField()

    class Meta:
        model = Company
        fields = [
            "id",
            "owner",
            "name",
            "bin",
            "description",
            "phone",
            "email",
            "address",
            "verification_status",
            "rating",
            "completed_orders",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["owner", "verification_status", "created_at", "updated_at"]

    @extend_schema_field(serializers.FloatField())
    def get_rating(self, obj):
        return obj.owner.received_reviews.aggregate(value=Avg("rating"))["value"] or 0

    @extend_schema_field(serializers.IntegerField())
    def get_completed_orders(self, obj):
        return Order.objects.filter(
            Q(shipper=obj.owner) | Q(carrier=obj.owner), status="completed"
        ).count()


class VehicleSerializer(serializers.ModelSerializer):
    class Meta:
        model = Vehicle
        fields = "__all__"
        read_only_fields = ["owner", "created_at", "updated_at"]

    def validate_status(self, value):
        if value == Vehicle.Status.BUSY:
            raise serializers.ValidationError("Busy status is managed by orders.")
        return value


class CargoSerializer(serializers.ModelSerializer):
    shipper = PublicUserSerializer(source="owner", read_only=True)
    matchScore = serializers.SerializerMethodField()
    offers_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = Cargo
        fields = "__all__"
        read_only_fields = ["owner", "created_at", "updated_at"]

    def validate(self, attrs):
        instance = self.instance

        def value(field):
            return attrs.get(field, getattr(instance, field, None))

        if value("from_city").strip().casefold() == value("to_city").strip().casefold():
            raise serializers.ValidationError("Departure and destination must differ.")
        # Old loading dates on immutable completed cargo do not block read access.
        if not instance or "loading_date" in attrs or attrs.get("status") == "active":
            if value("loading_date") < timezone.localdate():
                raise serializers.ValidationError(
                    {"loading_date": "Loading date cannot be in the past."}
                )
        if value("unloading_date") and value("unloading_date") < value("loading_date"):
            raise serializers.ValidationError({"unloading_date": "Unloading must follow loading."})
        if "status" in attrs and attrs["status"] not in ["draft", "active", "cancelled"]:
            raise serializers.ValidationError({"status": "This status is controlled by the order."})
        return attrs

    @extend_schema_field(serializers.IntegerField())
    def get_matchScore(self, obj):
        return match_score(
            obj,
            self.context.get("vehicle"),
            self.context.get("destination"),
            self.context.get("loading_date"),
        )


class OfferCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Offer
        fields = ["vehicle", "price", "message"]


class OfferUpdateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Offer
        fields = ["price", "message", "status"]


class OfferSerializer(serializers.ModelSerializer):
    carrier_profile = PublicUserSerializer(source="carrier", read_only=True)

    class Meta:
        model = Offer
        fields = "__all__"
        read_only_fields = ["cargo", "carrier", "status", "created_at", "updated_at"]


class OrderSerializer(serializers.ModelSerializer):
    shipper_profile = PublicUserSerializer(source="shipper", read_only=True)
    carrier_profile = PublicUserSerializer(source="carrier", read_only=True)
    conversation_id = serializers.IntegerField(source="conversation.id", read_only=True)

    class Meta:
        model = Order
        fields = "__all__"
        read_only_fields = [field.name for field in Order._meta.fields]


class StatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=Order.Status.choices)


class ConversationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Conversation
        fields = ["id", "order", "created_at"]
        read_only_fields = fields


class MessageSerializer(serializers.ModelSerializer):
    file_url = serializers.SerializerMethodField()
    attachment = serializers.FileField(
        write_only=True, required=False, validators=Message._meta.get_field("attachment").validators
    )

    class Meta:
        model = Message
        fields = [
            "id",
            "conversation",
            "sender",
            "type",
            "text",
            "attachment",
            "file_url",
            "latitude",
            "longitude",
            "created_at",
            "read_at",
        ]
        read_only_fields = ["id", "conversation", "sender", "created_at", "read_at"]

    def validate(self, attrs):
        kind = attrs.get("type", "text")
        attachment = attrs.get("attachment")
        if kind == "text" and not attrs.get("text", "").strip():
            raise serializers.ValidationError("Text is required.")
        if kind in ["image", "document"] and not attachment:
            raise serializers.ValidationError("Attachment is required.")
        if attachment:
            suffix = Path(attachment.name).suffix.lower()
            if (kind == "image" and suffix not in [".jpg", ".jpeg", ".png"]) or (
                kind == "document" and suffix != ".pdf"
            ):
                raise serializers.ValidationError("File does not match message type.")
            if kind not in ["image", "document"]:
                raise serializers.ValidationError(
                    "Attachments are allowed only for images and documents."
                )
        if kind == "location" and (attrs.get("latitude") is None or attrs.get("longitude") is None):
            raise serializers.ValidationError("Coordinates are required.")
        return attrs

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_file_url(self, obj):
        if not obj.attachment:
            return None
        return self.context["request"].build_absolute_uri(f"/api/messages/{obj.id}/file")


class ReviewSerializer(serializers.ModelSerializer):
    class Meta:
        model = Review
        fields = "__all__"
        read_only_fields = ["order", "author", "target_user", "created_at"]


class FavoriteSerializer(serializers.ModelSerializer):
    cargo = CargoSerializer(read_only=True)

    class Meta:
        model = FavoriteCargo
        fields = ["id", "cargo", "created_at"]


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = "__all__"
        read_only_fields = ["user", "type", "title", "message", "entity_id", "created_at"]


class AvatarSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["avatar"]
        extra_kwargs = {"avatar": {"required": True, "allow_null": False}}
