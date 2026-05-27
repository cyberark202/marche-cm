"""
Repository pattern base.
Repositories are the only layer that touches the ORM directly.
Services depend on repositories, not models.
"""
from __future__ import annotations

from typing import Any, Generic, TypeVar

from django.db import models
from django.db.models import QuerySet

ModelT = TypeVar("ModelT", bound=models.Model)


class BaseRepository(Generic[ModelT]):
    model: type[ModelT]

    def get_by_id(self, pk: Any) -> ModelT:
        return self.model.objects.get(pk=pk)

    def get_by_id_or_none(self, pk: Any) -> ModelT | None:
        try:
            return self.model.objects.get(pk=pk)
        except self.model.DoesNotExist:
            return None

    def all(self) -> QuerySet[ModelT]:
        return self.model.objects.all()

    def filter(self, **kwargs: Any) -> QuerySet[ModelT]:
        return self.model.objects.filter(**kwargs)

    def create(self, **kwargs: Any) -> ModelT:
        return self.model.objects.create(**kwargs)

    def update(self, instance: ModelT, **kwargs: Any) -> ModelT:
        for k, v in kwargs.items():
            setattr(instance, k, v)
        instance.save(update_fields=list(kwargs.keys()))
        return instance

    def delete(self, instance: ModelT) -> None:
        instance.delete()

    def exists(self, **kwargs: Any) -> bool:
        return self.model.objects.filter(**kwargs).exists()

    def count(self, **kwargs: Any) -> int:
        return self.model.objects.filter(**kwargs).count()
