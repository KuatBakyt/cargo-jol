from django.contrib import admin
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView
from marketplace import views
from rest_framework.routers import DefaultRouter

router = DefaultRouter(trailing_slash=False)
for prefix, view, basename in [
    ("companies", views.CompanyViewSet, "company"),
    ("vehicles", views.VehicleViewSet, "vehicle"),
    ("cargo", views.CargoViewSet, "cargo"),
    ("offers", views.OfferViewSet, "offer"),
    ("orders", views.OrderViewSet, "order"),
    ("conversations", views.ConversationViewSet, "conversation"),
    ("favorites", views.FavoriteViewSet, "favorite"),
    ("notifications", views.NotificationViewSet, "notification"),
]:
    router.register(prefix, view, basename=basename)

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/auth/register", views.RegisterView.as_view()),
    path("api/auth/login", views.LoginView.as_view()),
    path("api/auth/refresh", views.RefreshView.as_view()),
    path("api/auth/avatar", views.AvatarView.as_view()),
    path("api/auth/me", views.MeView.as_view()),
    path("api/messages/<int:pk>/file", views.MessageFileView.as_view()),
    path("api/schema", SpectacularAPIView.as_view(), name="schema"),
    path("api/docs", SpectacularSwaggerView.as_view(url_name="schema"), name="swagger-ui"),
    path("api/", include(router.urls)),
]
