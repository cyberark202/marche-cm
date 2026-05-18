from django.db import migrations

import apps.accounts.encrypted_fields


def encrypt_existing_user_pii(apps, schema_editor):
    user_model = apps.get_model("accounts", "User")
    fields = ["phone_number", "city", "location_label"]
    for user in user_model.objects.all().only("id", *fields).iterator():
        for field_name in fields:
            value = getattr(user, field_name, "")
            setattr(user, field_name, value or "")
        user.save(update_fields=fields)


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0006_compliancedocument_preview_image_user_city_and_more"),
    ]

    operations = [
        migrations.AlterField(
            model_name="user",
            name="phone_number",
            field=apps.accounts.encrypted_fields.EncryptedTextField(blank=True, default=""),
        ),
        migrations.AlterField(
            model_name="user",
            name="city",
            field=apps.accounts.encrypted_fields.EncryptedTextField(blank=True, default=""),
        ),
        migrations.AlterField(
            model_name="user",
            name="location_label",
            field=apps.accounts.encrypted_fields.EncryptedTextField(blank=True, default=""),
        ),
        migrations.RunPython(encrypt_existing_user_pii, migrations.RunPython.noop),
    ]
