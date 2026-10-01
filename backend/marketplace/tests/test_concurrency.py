from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from threading import Barrier
from unittest import skipUnless

from django.db import close_old_connections, connection
from django.test import TransactionTestCase
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from marketplace.models import Cargo, Offer, Order, User, Vehicle
from marketplace.services import accept_offer


@skipUnless(connection.vendor == "postgresql", "Row locking requires PostgreSQL")
class AssignmentConcurrencyTests(TransactionTestCase):
    def setUp(self):
        self.shipper = User.objects.create_user(
            email="shipper@test.com", phone="+77001111111", role="shipper"
        )
        self.carrier = User.objects.create_user(
            email="carrier@test.com", phone="+77002222222", role="carrier"
        )
        self.vehicle = Vehicle.objects.create(
            owner=self.carrier,
            brand="Volvo",
            model="FH",
            plate_number="ABC",
            body_type="tent",
            capacity_kg=1000,
            volume_m3=10,
            current_city="A",
        )
        self.cargo = Cargo.objects.create(
            owner=self.shipper,
            from_city="A",
            to_city="B",
            from_address="A1",
            to_address="B1",
            loading_date=timezone.localdate() + timedelta(days=1),
            cargo_name="Goods",
            cargo_type="general",
            weight_kg=100,
            volume_m3=1,
            body_type="tent",
            price=100,
            status="active",
        )
        self.offer = Offer.objects.create(
            cargo=self.cargo, carrier=self.carrier, vehicle=self.vehicle, price=100
        )

    def run_competing(self, offer_ids):
        barrier = Barrier(2)

        def worker(offer_id):
            close_old_connections()
            try:
                user = User.objects.get(pk=self.shipper.pk)
                barrier.wait(timeout=10)
                accept_offer(user, offer_id)
                return "accepted"
            except ValidationError:
                return "rejected"
            finally:
                close_old_connections()

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(worker, offer_ids))
        self.assertCountEqual(results, ["accepted", "rejected"])
        self.assertEqual(Order.objects.count(), 1)

    def test_same_offer_is_accepted_only_once(self):
        self.run_competing([self.offer.id, self.offer.id])

    def test_same_vehicle_cannot_take_two_cargo(self):
        cargo = Cargo.objects.get(pk=self.cargo.pk)
        cargo.pk = None
        cargo.save()
        other = Offer.objects.create(
            cargo=cargo, carrier=self.carrier, vehicle=self.vehicle, price=100
        )
        self.run_competing([self.offer.id, other.id])
