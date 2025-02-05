import logging
from rest_framework import viewsets
from rest_framework.response import Response
from rest_framework.decorators import action
from django.http import FileResponse
from rest_framework.parsers import MultiPartParser, FormParser
from .models import Document
from .serializers import DocumentSerializer

logger = logging.getLogger(__name__)

class DocumentViewSet(viewsets.ModelViewSet):
    queryset = Document.objects.all()
    serializer_class = DocumentSerializer
    parser_classes = (MultiPartParser, FormParser)

    @action(detail=True, methods=['get'])
    def download(self, request, pk=None):
        document = self.get_object()
        response = FileResponse(document.file)
        response['Content-Disposition'] = f'attachment; filename="{document.filename}"'
        return response

    def create(self, request, *args, **kwargs):
        logger.info(f"Получен файл: {request.FILES}")
        logger.info(f"Получены данные: {request.data}")
        
        try:
            file_obj = request.FILES.get('file')
            if not file_obj:
                return Response({'error': 'Файл не найден'}, status=400)

            document = Document.objects.create(
                file=file_obj,
                filename=request.data.get('filename', ''),
                lobby_name=request.data.get('lobby_name', ''),
                uploader=request.data.get('uploader', 'Аноним')
            )
            
            serializer = self.get_serializer(document)
            logger.info(f"Файл сохранен: {document.file.path}")
            return Response(serializer.data, status=201)
            
        except Exception as e:
            logger.error(f"Ошибка при сохранении файла: {str(e)}")
            return Response({'error': str(e)}, status=400) 