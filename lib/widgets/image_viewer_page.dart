import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class ImageViewerPage extends StatelessWidget {
  final String imageUrl;

  const ImageViewerPage({required this.imageUrl, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Просмотр изображения'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => Share.share(imageUrl),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () async {
              final status = await Permission.storage.request();
              if (status.isGranted) {
                final downloadDir = await getExternalStorageDirectory();
                final fileName = imageUrl.split('/').last;
                final targetPath = '${downloadDir!.path}/$fileName';
                
                // Скачиваем файл
                final response = await HttpClient().getUrl(Uri.parse(imageUrl));
                final httpResponse = await response.close();
                final bytes = await httpResponse.fold<List<int>>(
                  [],
                  (previous, element) => previous..addAll(element),
                );
                final file = File(targetPath);
                await file.writeAsBytes(bytes);
                
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Изображение сохранено')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            imageUrl,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Text('Ошибка загрузки изображения'),
              );
            },
          ),
        ),
      ),
    );
  }
} 