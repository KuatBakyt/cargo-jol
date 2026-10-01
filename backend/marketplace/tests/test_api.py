from datetime import timedelta

from django.utils import timezone
from rest_framework.test import APITestCase

from marketplace.models import Cargo, Order, User, Vehicle


class MarketplaceTests(APITestCase):
    def setUp(self):
        self.shipper = User.objects.create_user(
            email="shipper@example.com",
            phone="+77000000001",
            password="StrongPass123!",
            role="shipper",
        )
        self.carrier = User.objects.create_user(
            email="carrier@example.com",
            phone="+77000000002",
            password="StrongPass123!",
            role="carrier",
        )
        self.outsider = User.objects.create_user(
            email="other@example.com",
            phone="+77000000003",
            password="StrongPass123!",
            role="carrier",
        )
        self.vehicle = Vehicle.objects.create(
            owner=self.carrier,
            brand="Volvo",
            model="FH",
            plate_number="001ABC",
            body_type="tent",
            capacity_kg=20000,
            volume_m3=90,
            current_city="Алматы",
        )
        self.data = dict(
            from_city="Алматы",
            to_city="Астана",
            from_address="Склад 1",
            to_address="Склад 2",
            loading_date=str(timezone.localdate() + timedelta(days=2)),
            cargo_name="Мебель",
            cargo_type="furniture",
            weight_kg="1000",
            volume_m3="20",
            body_type="tent",
            price="150000",
            status="active",
        )
        self.client.force_authenticate(self.shipper)
        response = self.client.post("/api/cargo", self.data)
        self.assertEqual(response.status_code, 201, response.data)
        self.cargo_id = response.data["id"]

    def offer(self):
        self.client.force_authenticate(self.carrier)
        response = self.client.post(
            f"/api/cargo/{self.cargo_id}/offers",
            {"vehicle": self.vehicle.id, "price": "140000", "message": "Готов"},
        )
        self.assertEqual(response.status_code, 201, response.data)
        return response.data["id"]

    def order(self):
        offer = self.offer()
        self.client.force_authenticate(self.shipper)
        response = self.client.post(f"/api/offers/{offer}/accept")
        self.assertEqual(response.status_code, 201, response.data)
        return response.data

    def test_full_delivery_chat_and_reviews(self):
        order = self.order()
        self.client.force_authenticate(self.carrier)
        chat = order["conversation_id"]
        response = self.client.post(
            f"/api/conversations/{chat}/messages", {"type": "text", "text": "Выезжаю"}
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.client.force_authenticate(self.shipper)
        self.assertEqual(self.client.post(f"/api/conversations/{chat}/read").data["updated"], 1)
        self.client.force_authenticate(self.carrier)
        for state in ["heading_to_pickup", "loading", "in_transit", "delivered"]:
            response = self.client.patch(f"/api/orders/{order['id']}/status", {"status": state})
            self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            self.client.patch(
                f"/api/orders/{order['id']}/status", {"status": "completed"}
            ).status_code,
            403,
        )
        self.client.force_authenticate(self.shipper)
        self.assertEqual(
            self.client.patch(
                f"/api/orders/{order['id']}/status", {"status": "completed"}
            ).status_code,
            200,
        )
        self.assertEqual(
            self.client.post(
                f"/api/orders/{order['id']}/reviews", {"rating": 5, "comment": "Хорошо"}
            ).status_code,
            201,
        )
        self.assertEqual(
            self.client.post(f"/api/orders/{order['id']}/reviews", {"rating": 5}).status_code, 400
        )
        self.client.force_authenticate(self.carrier)
        self.assertEqual(
            self.client.post(f"/api/orders/{order['id']}/reviews", {"rating": 4}).status_code, 201
        )
        self.vehicle.refresh_from_db()
        self.assertEqual(self.vehicle.status, "available")
        self.assertEqual(self.vehicle.current_city, "Астана")
        self.assertEqual(Cargo.objects.get(pk=self.cargo_id).status, "completed")

    def test_no_double_assignment_and_private_order(self):
        offer = self.offer()
        self.client.force_authenticate(self.shipper)
        response = self.client.post(f"/api/offers/{offer}/accept")
        self.assertEqual(response.status_code, 201)
        self.assertEqual(self.client.post(f"/api/offers/{offer}/accept").status_code, 400)
        self.assertEqual(Order.objects.count(), 1)
        self.client.force_authenticate(self.outsider)
        self.assertEqual(self.client.get(f"/api/orders/{response.data['id']}").status_code, 404)
        self.assertEqual(
            self.client.get(
                f"/api/conversations/{response.data['conversation_id']}/messages"
            ).status_code,
            404,
        )

    def test_roles_ownership_capacity_and_validation(self):
        self.client.force_authenticate(self.carrier)
        self.assertEqual(self.client.post("/api/cargo", self.data).status_code, 403)
        self.assertEqual(
            self.client.patch(f"/api/cargo/{self.cargo_id}", {"price": "1"}).status_code, 403
        )
        self.client.force_authenticate(self.outsider)
        self.assertEqual(
            self.client.post(
                f"/api/cargo/{self.cargo_id}/offers", {"vehicle": self.vehicle.id, "price": "100"}
            ).status_code,
            403,
        )
        self.client.force_authenticate(self.shipper)
        for patch in [
            {"price": "-1"},
            {"weight_kg": "0"},
            {"to_city": "Алматы"},
            {"loading_date": "2000-01-01"},
        ]:
            self.assertEqual(
                self.client.patch(f"/api/cargo/{self.cargo_id}", patch).status_code, 400
            )
        self.vehicle.capacity_kg = 100
        self.vehicle.save()
        self.client.force_authenticate(self.carrier)
        self.assertEqual(
            self.client.post(
                f"/api/cargo/{self.cargo_id}/offers", {"vehicle": self.vehicle.id, "price": "100"}
            ).status_code,
            400,
        )

    def test_favorites_filters_and_cancellation(self):
        self.client.force_authenticate(self.carrier)
        self.assertEqual(self.client.post(f"/api/cargo/{self.cargo_id}/favorite").status_code, 201)
        self.assertEqual(self.client.get("/api/favorites").data["count"], 1)
        self.assertEqual(
            self.client.get("/api/cargo?from=Алматы&price_min=160000").data["count"], 0
        )
        order = self.order()
        self.assertEqual(
            self.client.patch(
                f"/api/orders/{order['id']}/status", {"status": "cancelled"}
            ).status_code,
            200,
        )
        self.vehicle.refresh_from_db()
        self.assertEqual(self.vehicle.status, "available")

    def test_jwt_refresh_rotation_and_me(self):
        self.client.force_authenticate(None)
        self.assertEqual(self.client.get("/api/cargo").status_code, 401)
        response = self.client.post(
            "/api/auth/login", {"email": "CARRIER@example.com", "password": "StrongPass123!"}
        )
        self.assertEqual(response.status_code, 200)
        refresh = response.data["refresh"]
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + response.data["access"])
        self.assertEqual(self.client.get("/api/auth/me").data["id"], self.carrier.id)
        self.assertEqual(
            self.client.post("/api/auth/refresh", {"refresh": refresh}).status_code, 200
        )
        self.assertEqual(
            self.client.post("/api/auth/refresh", {"refresh": refresh}).status_code, 401
        )

    def test_review_requires_completion_and_transition_order(self):
        order = self.order()
        self.assertEqual(
            self.client.post(f"/api/orders/{order['id']}/reviews", {"rating": 5}).status_code, 400
        )
        self.client.force_authenticate(self.carrier)
        self.assertEqual(
            self.client.patch(
                f"/api/orders/{order['id']}/status", {"status": "delivered"}
            ).status_code,
            400,
        )

    def test_private_files_and_invalid_upload(self):
        import tempfile

        from django.core.files.uploadedfile import SimpleUploadedFile
        from django.test import override_settings

        order = self.order()
        url = f"/api/conversations/{order['conversation_id']}/messages"
        with tempfile.TemporaryDirectory() as directory, override_settings(MEDIA_ROOT=directory):
            response = self.client.post(
                url,
                {
                    "type": "document",
                    "attachment": SimpleUploadedFile("invoice.pdf", b"%PDF-1.4\n%%EOF"),
                },
                format="multipart",
            )
            self.assertEqual(response.status_code, 201, response.data)
            file_url = f"/api/messages/{response.data['id']}/file"
            download = self.client.get(file_url)
            self.assertEqual(download.status_code, 200)
            self.assertTrue(download["Content-Disposition"].startswith("attachment;"))
            self.assertTrue(b"".join(download.streaming_content).startswith(b"%PDF-"))
            bad = self.client.post(
                url,
                {"type": "image", "attachment": SimpleUploadedFile("photo.png", b"fake image")},
                format="multipart",
            )
            self.assertEqual(bad.status_code, 400)
            self.client.force_authenticate(self.outsider)
            self.assertEqual(self.client.get(file_url).status_code, 404)

    def test_other_pending_offer_is_rejected(self):
        first = self.offer()
        vehicle = Vehicle.objects.create(
            owner=self.outsider,
            brand="MAN",
            model="TGX",
            plate_number="002ABC",
            body_type="tent",
            capacity_kg=20000,
            volume_m3=90,
            current_city="Алматы",
        )
        self.client.force_authenticate(self.outsider)
        response = self.client.post(
            f"/api/cargo/{self.cargo_id}/offers", {"vehicle": vehicle.id, "price": "130000"}
        )
        self.assertEqual(response.status_code, 201)
        second_id = response.data["id"]
        self.client.force_authenticate(self.shipper)
        self.assertEqual(self.client.post(f"/api/offers/{first}/accept").status_code, 201)
        from marketplace.models import Offer

        self.assertEqual(Offer.objects.get(pk=second_id).status, "rejected")
