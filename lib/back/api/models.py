from django.db import models
from django.core.exceptions import ValidationError

def validate_file_extension(value):
    if not value.name.endswith('.pdf'):
        raise ValidationError('Только PDF файлы разрешены')


class Document(models.Model):
    file = models.FileField(
        upload_to='documents/',
        validators=[validate_file_extension]
    )
    filename = models.CharField(max_length=255)
    upload_date = models.DateTimeField(auto_now_add=True)
    lobby_name = models.CharField(max_length=255)
    uploader = models.CharField(max_length=255)

    def __str__(self):
        return self.filename