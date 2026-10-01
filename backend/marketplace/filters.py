import django_filters

from .models import Cargo


class CargoFilter(django_filters.FilterSet):
    # `from` is a Python keyword, so aliases are declared in base_filters below.
    loading_date = django_filters.DateFilter()
    loading_date_min = django_filters.DateFilter(field_name="loading_date", lookup_expr="gte")
    loading_date_max = django_filters.DateFilter(field_name="loading_date", lookup_expr="lte")
    weight_min = django_filters.NumberFilter(field_name="weight_kg", lookup_expr="gte")
    weight_max = django_filters.NumberFilter(field_name="weight_kg", lookup_expr="lte")
    price_min = django_filters.NumberFilter(field_name="price", lookup_expr="gte")
    price_max = django_filters.NumberFilter(field_name="price", lookup_expr="lte")

    class Meta:
        model = Cargo
        fields = ["body_type", "status"]


CargoFilter.base_filters["from"] = django_filters.CharFilter(
    field_name="from_city", lookup_expr="iexact"
)
CargoFilter.base_filters["to"] = django_filters.CharFilter(
    field_name="to_city", lookup_expr="iexact"
)
