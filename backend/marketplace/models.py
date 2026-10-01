from decimal import Decimal
from pathlib import Path
from uuid import uuid4

from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.core.validators import MaxValueValidator, MinValueValidator, RegexValidator
from django.db import models
from django.db.models import Q

from .validators import validate_attachment


class UserManager(BaseUserManager):
    def create_user(self, email, password=None, **fields):
        user = self.model(email=self.normalize_email(email).lower(), **fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **fields):
        fields.setdefault("is_staff", True)
        fields.setdefault("is_superuser", True)
        fields.setdefault("role", "shipper")
        if not fields["is_staff"] or not fields["is_superuser"]:
            raise ValueError("Superuser needs is_staff and is_superuser.")
        return self.create_user(email, password, **fields)


class User(AbstractUser):
    class Role(models.TextChoices):
        CARRIER = "carrier", "Перевозчик"
        SHIPPER = "shipper", "Грузовладелец"

    username = None
    email = models.EmailField(unique=True)
    phone = models.CharField(
        max_length=16,
        unique=True,
        validators=[
            RegexValidator(r"^\+[1-9]\d{7,14}$", "Use international format, e.g. +77001234567.")
        ],
    )
    role = models.CharField(max_length=10, choices=Role.choices)
    avatar = models.ImageField(upload_to="avatars/", blank=True, validators=[validate_attachment])
    is_phone_verified = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = ["phone"]
    objects = UserManager()


class Timestamped(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class Company(Timestamped):
    class Verification(models.TextChoices):
        UNVERIFIED = "unverified", "Не проверена"
        PENDING = "pending", "На проверке"
        VERIFIED = "verified", "Проверена"
        REJECTED = "rejected", "Отклонена"

    owner = models.OneToOneField(User, on_delete=models.CASCADE, related_name="company")
    name = models.CharField(max_length=200)
    bin = models.CharField(max_length=12, unique=True, validators=[RegexValidator(r"^\d{12}$")])
    description = models.TextField(blank=True)
    phone = models.CharField(max_length=16, blank=True)
    email = models.EmailField(blank=True)
    address = models.CharField(max_length=255, blank=True)
    verification_status = models.CharField(
        max_length=12, choices=Verification.choices, default=Verification.UNVERIFIED
    )


class Vehicle(Timestamped):
    class Status(models.TextChoices):
        AVAILABLE = "available", "Свободен"
        BUSY = "busy", "Занят"
        INACTIVE = "inactive", "Неактивен"

    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name="vehicles")
    brand = models.CharField(max_length=80)
    model = models.CharField(max_length=80)
    plate_number = models.CharField(max_length=20, unique=True)
    body_type = models.CharField(max_length=30)
    capacity_kg = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal("0.01"))]
    )
    volume_m3 = models.DecimalField(
        max_digits=10, decimal_places=2, validators=[MinValueValidator(0)]
    )
    current_city = models.CharField(max_length=120)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.AVAILABLE)


class Cargo(Timestamped):
    class Status(models.TextChoices):
        DRAFT = "draft", "Черновик"
        ACTIVE = "active", "Опубликован"
        ASSIGNED = "assigned", "Исполнитель выбран"
        IN_TRANSIT = "in_transit", "В пути"
        COMPLETED = "completed", "Завершён"
        CANCELLED = "cancelled", "Отменён"

    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name="cargo")
    from_city = models.CharField(max_length=120)
    from_address = models.CharField(max_length=255)
    to_city = models.CharField(max_length=120)
    to_address = models.CharField(max_length=255)
    loading_date = models.DateField()
    unloading_date = models.DateField(null=True, blank=True)
    cargo_name = models.CharField(max_length=200)
    cargo_type = models.CharField(max_length=80)
    weight_kg = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal("0.01"))]
    )
    volume_m3 = models.DecimalField(
        max_digits=10, decimal_places=2, validators=[MinValueValidator(0)]
    )
    body_type = models.CharField(max_length=30)
    price = models.DecimalField(
        max_digits=14, decimal_places=2, validators=[MinValueValidator(Decimal("0.01"))]
    )
    payment_type = models.CharField(max_length=30, default="bank_transfer")
    description = models.TextField(blank=True)
    status = models.CharField(
        max_length=12, choices=Status.choices, default=Status.DRAFT, db_index=True
    )

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["from_city", "to_city", "loading_date"])]
        constraints = [
            models.CheckConstraint(
                condition=Q(price__gt=0, weight_kg__gt=0, volume_m3__gte=0),
                name="cargo_positive_values",
            )
        ]


class Offer(Timestamped):
    class Status(models.TextChoices):
        PENDING = "pending", "Ожидает"
        ACCEPTED = "accepted", "Принято"
        REJECTED = "rejected", "Отклонено"
        CANCELLED = "cancelled", "Отменено"

    cargo = models.ForeignKey(Cargo, on_delete=models.CASCADE, related_name="offers")
    carrier = models.ForeignKey(User, on_delete=models.PROTECT, related_name="offers")
    vehicle = models.ForeignKey(Vehicle, on_delete=models.PROTECT, related_name="offers")
    price = models.DecimalField(
        max_digits=14, decimal_places=2, validators=[MinValueValidator(Decimal("0.01"))]
    )
    message = models.TextField(blank=True)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.PENDING)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["cargo", "carrier"],
                condition=Q(status="pending"),
                name="one_pending_offer_per_carrier",
            )
        ]


class Order(Timestamped):
    class Status(models.TextChoices):
        SELECTED = "carrier_selected", "Перевозчик выбран"
        HEADING = "heading_to_pickup", "Машина направляется"
        LOADING = "loading", "На загрузке"
        IN_TRANSIT = "in_transit", "В пути"
        DELIVERED = "delivered", "Доставлено"
        COMPLETED = "completed", "Завершено"
        CANCELLED = "cancelled", "Отменено"

    cargo = models.OneToOneField(Cargo, on_delete=models.PROTECT, related_name="order")
    offer = models.OneToOneField(Offer, on_delete=models.PROTECT, related_name="order")
    shipper = models.ForeignKey(User, on_delete=models.PROTECT, related_name="shipped_orders")
    carrier = models.ForeignKey(User, on_delete=models.PROTECT, related_name="carried_orders")
    vehicle = models.ForeignKey(Vehicle, on_delete=models.PROTECT, related_name="orders")
    agreed_price = models.DecimalField(max_digits=14, decimal_places=2)
    status = models.CharField(max_length=24, choices=Status.choices, default=Status.SELECTED)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["vehicle"],
                condition=~Q(status__in=["completed", "cancelled"]),
                name="one_active_order_per_vehicle",
            )
        ]


class Conversation(models.Model):
    order = models.OneToOneField(Order, on_delete=models.CASCADE, related_name="conversation")
    created_at = models.DateTimeField(auto_now_add=True)


def attachment_path(instance, filename):
    return f"messages/{instance.conversation_id}/{uuid4().hex}{Path(filename).suffix.lower()}"


class Message(models.Model):
    class Type(models.TextChoices):
        TEXT = "text", "Текст"
        IMAGE = "image", "Фото"
        DOCUMENT = "document", "Документ"
        LOCATION = "location", "Местоположение"

    conversation = models.ForeignKey(
        Conversation, on_delete=models.CASCADE, related_name="messages"
    )
    sender = models.ForeignKey(User, on_delete=models.PROTECT)
    type = models.CharField(max_length=10, choices=Type.choices, default=Type.TEXT)
    text = models.TextField(blank=True)
    attachment = models.FileField(
        upload_to=attachment_path, blank=True, validators=[validate_attachment]
    )
    latitude = models.DecimalField(
        max_digits=10,
        decimal_places=7,
        null=True,
        blank=True,
        validators=[MinValueValidator(-90), MaxValueValidator(90)],
    )
    longitude = models.DecimalField(
        max_digits=10,
        decimal_places=7,
        null=True,
        blank=True,
        validators=[MinValueValidator(-180), MaxValueValidator(180)],
    )
    created_at = models.DateTimeField(auto_now_add=True)
    read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["created_at", "id"]


class Review(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="reviews")
    author = models.ForeignKey(User, on_delete=models.PROTECT, related_name="written_reviews")
    target_user = models.ForeignKey(User, on_delete=models.PROTECT, related_name="received_reviews")
    rating = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    comment = models.TextField(blank=True, max_length=2000)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["order", "author"], name="one_review_per_author_and_order"
            )
        ]


class FavoriteCargo(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="favorites")
    cargo = models.ForeignKey(Cargo, on_delete=models.CASCADE)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["user", "cargo"], name="unique_favorite")]


class Notification(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="notifications")
    type = models.CharField(max_length=40)
    title = models.CharField(max_length=160)
    message = models.TextField(blank=True)
    entity_id = models.PositiveBigIntegerField(null=True)
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
