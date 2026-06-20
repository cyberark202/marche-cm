# -*- coding: utf-8 -*-  (substep API : l'upload UI echoue sur web, cf Finding #3)
from pathlib import Path
from django.core.files.base import ContentFile
from apps.accounts.models import ComplianceDocument

img = Path(r"E:/project/Marche CM/qa_e2e/media/product1.jpg").read_bytes()
for dt in ["PASSPORT", "DRIVER_LICENSE"]:
    doc, created = ComplianceDocument.objects.get_or_create(
        user_id=33, doc_type=dt, defaults={"status": "PENDING"}
    )
    if not doc.file:
        doc.file.save(f"e2e_driver33_{dt}.jpg", ContentFile(img), save=True)
    print(f"  doc id={doc.id} type={doc.doc_type} status={doc.status} file={bool(doc.file)} created={created}")
print("KYC docs ready (PENDING) for admin review.")
