import importlib

from .test_settings import *

DATABASES = importlib.import_module("config.settings").DATABASES
