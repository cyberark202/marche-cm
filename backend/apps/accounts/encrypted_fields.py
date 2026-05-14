from django.db import models

from .field_crypto import decrypt_value, encrypt_value


class EncryptedTextField(models.TextField):
    description = "Text field encrypted at rest (application-level)"

    def from_db_value(self, value, expression, connection):
        return self.to_python(value)

    def to_python(self, value):
        if value is None:
            return value
        if isinstance(value, str):
            return decrypt_value(value)
        return value

    def get_prep_value(self, value):
        value = super().get_prep_value(value)
        if value is None:
            return value
        return encrypt_value(str(value))
