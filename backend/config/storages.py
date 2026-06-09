from storages.backends.s3boto3 import S3Boto3Storage

class S3MediaStorage(S3Boto3Storage):
    """
    Custom S3 storage backend that:
    1. Generates public, unsigned, CDN-backed URLs for public media (products, avatars).
    2. Generates private, signed URLs directly from S3 for secure documents (compliance, delivery proofs, etc.).
    """
    def url(self, name, parameters=None, expire=None, http_method=None):
        if name.startswith(("products/", "avatars/")):
            # Public unsigned CDN URL
            old_auth = self.querystring_auth
            self.querystring_auth = False
            url_val = super().url(name, parameters, expire, http_method)
            self.querystring_auth = old_auth
            return url_val
        else:
            # Private signed S3 URL
            old_auth = self.querystring_auth
            old_domain = self.custom_domain
            self.querystring_auth = True
            self.custom_domain = None
            url_val = super().url(name, parameters, expire, http_method)
            self.querystring_auth = old_auth
            self.custom_domain = old_domain
            return url_val
