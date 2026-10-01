"""Business operations. All competing mutations lock cargo before vehicle/order."""

from django.db import transaction
from django.db.models import Avg
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied, ValidationError

from .models import Cargo, Conversation, Notification, Offer, Order, Vehicle


def notify(user, kind, title, entity_id):
    return Notification.objects.create(
        user_id=getattr(user, "pk", user), type=kind, title=title, entity_id=entity_id
    )


def require_role(user, role):
    if user.role != role:
        raise PermissionDenied(f"This action requires role {role}.")


def check_vehicle(vehicle, cargo, carrier):
    if vehicle.owner_id != carrier.id:
        raise PermissionDenied("Use your own vehicle.")
    if vehicle.status != Vehicle.Status.AVAILABLE:
        raise ValidationError("Vehicle is not available.")
    if vehicle.capacity_kg < cargo.weight_kg or vehicle.volume_m3 < cargo.volume_m3:
        raise ValidationError("Vehicle capacity or volume is too small.")
    if vehicle.body_type != cargo.body_type:
        raise ValidationError("Vehicle body type does not match cargo.")
    if vehicle.orders.exclude(status__in=[Order.Status.COMPLETED, Order.Status.CANCELLED]).exists():
        raise ValidationError("Vehicle already has an active order.")


@transaction.atomic
def create_offer(user, cargo_id, data):
    require_role(user, "carrier")
    cargo = Cargo.objects.select_for_update().get(pk=cargo_id)
    if cargo.status != Cargo.Status.ACTIVE or cargo.loading_date < timezone.localdate():
        raise ValidationError("Cargo is not open for offers.")
    if cargo.owner_id == user.id:
        raise PermissionDenied("You cannot offer on your own cargo.")
    vehicle = Vehicle.objects.select_for_update().get(pk=data["vehicle"].id)
    check_vehicle(vehicle, cargo, user)
    if Offer.objects.filter(cargo=cargo, carrier=user, status=Offer.Status.PENDING).exists():
        raise ValidationError("You already have a pending offer.")
    offer = Offer.objects.create(cargo=cargo, carrier=user, **data)
    notify(cargo.owner, "new_offer", "Новое предложение", offer.id)
    return offer


@transaction.atomic
def accept_offer(user, offer_id):
    # Read only the immutable FK first; acquire the shared cargo lock before reading status.
    cargo_id = Offer.objects.values_list("cargo_id", flat=True).get(pk=offer_id)
    cargo = Cargo.objects.select_for_update().get(pk=cargo_id)
    if cargo.owner_id != user.id:
        raise PermissionDenied("Only cargo owner can accept an offer.")
    offer = Offer.objects.select_related("carrier").get(pk=offer_id)
    if cargo.status != Cargo.Status.ACTIVE or offer.status != Offer.Status.PENDING:
        raise ValidationError("Cargo or offer is no longer available.")
    if cargo.loading_date < timezone.localdate():
        raise ValidationError("Loading date has passed.")
    vehicle = Vehicle.objects.select_for_update().get(pk=offer.vehicle_id)
    check_vehicle(vehicle, cargo, offer.carrier)
    rejected = list(cargo.offers.filter(status=Offer.Status.PENDING).exclude(pk=offer.id))
    cargo.offers.filter(status=Offer.Status.PENDING).exclude(pk=offer.id).update(
        status=Offer.Status.REJECTED
    )
    offer.status = Offer.Status.ACCEPTED
    offer.save(update_fields=["status", "updated_at"])
    cargo.status = Cargo.Status.ASSIGNED
    cargo.save(update_fields=["status", "updated_at"])
    vehicle.status = Vehicle.Status.BUSY
    vehicle.save(update_fields=["status", "updated_at"])
    order = Order.objects.create(
        cargo=cargo,
        offer=offer,
        shipper=cargo.owner,
        carrier=offer.carrier,
        vehicle=vehicle,
        agreed_price=offer.price,
    )
    Conversation.objects.create(order=order)
    notify(offer.carrier, "offer_accepted", "Предложение принято", order.id)
    for item in rejected:
        notify(item.carrier, "offer_rejected", "Предложение отклонено", item.id)
    return order


@transaction.atomic
def change_offer(user, offer_id, data=None, action=None):
    cargo_id = Offer.objects.values_list("cargo_id", flat=True).get(pk=offer_id)
    cargo = Cargo.objects.select_for_update().get(pk=cargo_id)
    offer = Offer.objects.get(pk=offer_id)
    if offer.status != Offer.Status.PENDING or cargo.status != Cargo.Status.ACTIVE:
        raise ValidationError("Only pending offers on active cargo can be changed.")
    if action == "reject":
        if user.id != cargo.owner_id:
            raise PermissionDenied("Only cargo owner can reject.")
        offer.status = Offer.Status.REJECTED
        notify(offer.carrier, "offer_rejected", "Предложение отклонено", offer.id)
    else:
        if user.id != offer.carrier_id:
            raise PermissionDenied("Only offer author can change it.")
        for key, value in (data or {}).items():
            if key == "status" and value != Offer.Status.CANCELLED:
                raise ValidationError("Only cancellation is allowed through PATCH.")
            setattr(offer, key, value)
    offer.save()
    return offer


NEXT_STATUS = {
    Order.Status.SELECTED: Order.Status.HEADING,
    Order.Status.HEADING: Order.Status.LOADING,
    Order.Status.LOADING: Order.Status.IN_TRANSIT,
    Order.Status.IN_TRANSIT: Order.Status.DELIVERED,
    Order.Status.DELIVERED: Order.Status.COMPLETED,
}


@transaction.atomic
def change_order_status(user, order_id, new_status):
    initial = Order.objects.only("cargo_id", "vehicle_id").get(pk=order_id)
    cargo = Cargo.objects.select_for_update().get(pk=initial.cargo_id)
    vehicle = Vehicle.objects.select_for_update().get(pk=initial.vehicle_id)
    order = Order.objects.select_for_update().get(pk=order_id)
    if user.id not in [order.shipper_id, order.carrier_id]:
        raise PermissionDenied("Only order participants can change status.")
    if new_status == Order.Status.CANCELLED:
        if order.status not in [Order.Status.SELECTED, Order.Status.HEADING, Order.Status.LOADING]:
            raise ValidationError("Cancellation is allowed only before departure.")
        cargo.status = Cargo.Status.CANCELLED
    else:
        if NEXT_STATUS.get(order.status) != new_status:
            raise ValidationError("Invalid status transition.")
        if new_status == Order.Status.COMPLETED:
            if user.id != order.shipper_id:
                raise PermissionDenied("Only shipper confirms completion.")
            cargo.status = Cargo.Status.COMPLETED
            order.completed_at = timezone.now()
        else:
            if user.id != order.carrier_id:
                raise PermissionDenied("Only carrier updates transport progress.")
            if new_status == Order.Status.IN_TRANSIT:
                cargo.status = Cargo.Status.IN_TRANSIT
    order.status = new_status
    order.save(update_fields=["status", "completed_at", "updated_at"])
    cargo.save(update_fields=["status", "updated_at"])
    if new_status in [Order.Status.COMPLETED, Order.Status.CANCELLED]:
        vehicle.status = Vehicle.Status.AVAILABLE
        if new_status == Order.Status.COMPLETED:
            vehicle.current_city = cargo.to_city
        vehicle.save(update_fields=["status", "current_city", "updated_at"])
    other_id = order.carrier_id if user.id == order.shipper_id else order.shipper_id
    notify(other_id, "order_status", f"Статус перевозки: {new_status}", order.id)
    return order


def match_score(cargo, vehicle=None, destination=None, loading_date=None):
    """No AI: explicit requested criteria; missing criteria contribute zero points."""
    score = 0
    if vehicle:
        route_matches = cargo.from_city.casefold() == vehicle.current_city.casefold()
        if destination:
            route_matches = route_matches and cargo.to_city.casefold() == destination.casefold()
        if route_matches:
            score += 40
        if cargo.body_type == vehicle.body_type:
            score += 25
        if cargo.weight_kg <= vehicle.capacity_kg and cargo.volume_m3 <= vehicle.volume_m3:
            score += 15
    if loading_date and cargo.loading_date.isoformat() == loading_date:
        score += 10
    rating = getattr(cargo.owner, "review_rating", None)
    if rating is None:
        rating = cargo.owner.received_reviews.aggregate(value=Avg("rating"))["value"] or 0
    return round(score + float(rating) / 5 * 10)


def notify_matches(cargo):
    vehicles = Vehicle.objects.filter(
        status=Vehicle.Status.AVAILABLE,
        current_city__iexact=cargo.from_city,
        body_type=cargo.body_type,
        capacity_kg__gte=cargo.weight_kg,
        volume_m3__gte=cargo.volume_m3,
    )
    for owner_id in vehicles.values_list("owner_id", flat=True).distinct():
        Notification.objects.create(
            user_id=owner_id,
            type="matching_cargo",
            title="Новый подходящий груз",
            entity_id=cargo.id,
        )
