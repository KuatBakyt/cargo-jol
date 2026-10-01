import os

os.environ.setdefault("DEBUG", "true")
from .settings import *

# Fast portable tests; PostgreSQL locking tests use config.postgres_test_settings.
DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": ":memory:"}}
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
REST_FRAMEWORK = {**REST_FRAMEWORK, "DEFAULT_THROTTLE_CLASSES": []}
