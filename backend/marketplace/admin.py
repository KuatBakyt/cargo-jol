from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

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


@admin.register(User)
class CargoUserAdmin(UserAdmin):
    ordering = ["email"]
    list_display = ["email", "phone", "role", "is_phone_verified", "is_staff"]
    search_fields = ["email", "phone"]
    fieldsets = (
        (None, {"fields": ("email", "password")}),
        (
            "Profile",
            {"fields": ("first_name", "last_name", "phone", "role", "avatar", "is_phone_verified")},
        ),
        (
            "Access",
            {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")},
        ),
    )
    add_fieldsets = (
        (
            None,
            {"classes": ("wide",), "fields": ("email", "phone", "role", "password1", "password2")},
        ),
    )


@admin.register(Company)
class CompanyAdmin(admin.ModelAdmin):
    list_display = ["name", "bin", "owner", "verification_status"]
    list_filter = ["verification_status"]
    actions = ["verify", "reject"]

    @admin.action(description="Approve pending companies")
    def verify(self, request, queryset):
        queryset.filter(verification_status="pending").update(verification_status="verified")

    @admin.action(description="Reject pending companies")
    def reject(self, request, queryset):
        queryset.filter(verification_status="pending").update(verification_status="rejected")


# Business status changes must go through services, not generic admin editing.
class ReadOnlyBusinessAdmin(admin.ModelAdmin):
    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


for model in [
    Cargo,
    Offer,
    Order,
    Vehicle,
    Conversation,
    Message,
    Review,
    FavoriteCargo,
    Notification,
]:
    admin.site.register(model, ReadOnlyBusinessAdmin)
