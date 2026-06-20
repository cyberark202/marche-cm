from django.contrib.auth import get_user_model

U = get_user_model()
qs = U.objects.filter(email__iexact="driver.e2e@marche-cm.local")
print("existing driver.e2e:", list(qs.values_list("id", "username", "role")))
qs.delete()
print("remaining:", U.objects.filter(email__iexact="driver.e2e@marche-cm.local").count())
