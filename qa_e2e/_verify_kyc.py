from apps.accounts.models import ComplianceDocument

docs = ComplianceDocument.objects.filter(user_id=33).order_by("id")
print(f"ComplianceDocument for user 33: {docs.count()}")
for d in docs:
    print(f"  id={d.id} doc_type={d.doc_type} status={d.status} created={d.created_at:%H:%M:%S} "
          f"mime={getattr(d, 'mime_type', '?')} file={bool(d.file)}")
