import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class PdfViewerPage extends StatelessWidget {
  final String filePath;

  const PdfViewerPage({required this.filePath, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Просмотр PDF'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => Share.share(filePath),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () async {
              final status = await Permission.storage.request();
              if (status.isGranted) {
                final downloadDir = await getExternalStorageDirectory();
                final fileName = filePath.split('/').last;
                final targetPath = '${downloadDir!.path}/$fileName';
                
                // Скачиваем файл
                final response = await HttpClient().getUrl(Uri.parse(filePath));
                final httpResponse = await response.close();
                final bytes = await httpResponse.fold<List<int>>(
                  [],
                  (previous, element) => previous..addAll(element),
                );
                final file = File(targetPath);
                await file.writeAsBytes(bytes);
                
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PDF файл сохранен')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: SfPdfViewer.network(filePath),
    );
  }
} 