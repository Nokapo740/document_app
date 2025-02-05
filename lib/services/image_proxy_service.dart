class ImageProxyService {
  static String getProxiedImageUrl(String originalUrl) {
    if (originalUrl.isEmpty) return '';
    // Используем imgproxy.xyz как публичный прокси-сервер для изображений
    // Также можно использовать другие сервисы: images.weserv.nl, wsrv.nl и т.д.
    return 'https://images.weserv.nl/?url=${Uri.encodeComponent(originalUrl)}';
  }
}
