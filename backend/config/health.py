from django.utils import timezone
from rest_framework import permissions, response
from rest_framework.views import APIView


class HealthView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        return response.Response(
            {
                "status": "ok",
                "service": "marche-cm-backend",
                "timestamp": timezone.now().isoformat(),
            }
        )
