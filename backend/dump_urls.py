import os
import sys
import django

# Setup django environment
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.urls import get_resolver
from rest_framework.schemas.generators import EndpointEnumerator

resolver = get_resolver()
enumerator = EndpointEnumerator()
endpoints = enumerator.get_api_endpoints()

print("--- Backend Endpoints ---")
for path, method, callback in endpoints:
    if path.startswith('/api/'):
        print(f"{method} {path}")
