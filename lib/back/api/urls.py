
from django.contrib import admin
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import  DocumentViewSet # LobbyViewSet, MessageViewSet,
from django.conf import settings
from django.conf.urls.static import static

router = DefaultRouter()
# router.register(r'lobbies', LobbyViewSet)
# router.register(r'messages', MessageViewSet)
router.register(r'documents', DocumentViewSet)

urlpatterns = [
    path('', include(router.urls)),
    # path('api-auth/', include('rest_framework.urls'))
]
