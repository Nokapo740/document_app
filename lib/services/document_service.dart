import 'package:file_picker/file_picker.dart';
import '../backend.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

class DocumentService {
  final ApiService _apiService = ApiService();
  final Dio _dio = Dio();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.file',
    ],
  );

  // Загрузка документа
  Future<bool> uploadDocument({
    required PlatformFile file,
    required String lobbyName,
    required String uploader,
    required BuildContext context,
  }) async {
    try {
      if (file.bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка: файл пуст')),
        );
        return false;
      }

      // Обработка кириллического имени файла
      String sanitizedFileName = Uri.encodeComponent(file.name)
          .replaceAll('%20', '_')  // Заменяем пробелы на подчеркивания
          .replaceAll(RegExp(r'[^\w\s\-\.]'), '_'); // Заменяем специальные символы

      // Создаем уникальное имя файла с временной меткой
      String uniqueFileName = '${DateTime.now().millisecondsSinceEpoch}_$sanitizedFileName';
      
      print('Оригинальное имя файла: ${file.name}');
      print('Обработанное имя файла: $uniqueFileName');

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromBytes(
          file.bytes!,
          filename: uniqueFileName,
          contentType: MediaType('application', 'pdf'),
        ),
        'filename': file.name, // Сохраняем оригинальное имя для отображения
        'lobby_name': lobbyName,
        'uploader': uploader,
      });

      print('Отправка файла: ${file.name}');
      print('Размер файла: ${file.bytes!.length} bytes');
      print('Lobby name: $lobbyName');
      print('Uploader: $uploader');

      final response = await _apiService.postDataFormData(
        context,
        'documents/',
        formData,
      );

      if (response == null) {
        print('Ошибка: Ответ от сервера пуст');
        return false;
      }

      print('Ответ сервера: $response');
      return true;
    } catch (e, stackTrace) {
      print('Ошибка при загрузке документа: $e');
      print('Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при загрузке документа: $e')),
      );
      return false;
    }
  }

  // Получение списка документов для лобби
  Future<List<Map<String, dynamic>>> getDocumentsForLobby(String lobbyName) async {
    try {
      final documents = await _apiService.getDataList(
        'documents/?lobby_name=$lobbyName',
        false,
      );
      // Добавляем отладочную информацию
      print('Получены документы для лобби $lobbyName:');
      for (var doc in documents) {
        print('Документ: ${doc['filename']}, URL: ${doc['file_url'] ?? doc['file']}');
      }
      return documents;
    } catch (e) {
      print('Ошибка при получении документов: $e');
      return [];
    }
  }

  // Скачивание документа
  Future<void> downloadDocument(String fileUrl, BuildContext context) async {
    try {
      print('Начало скачивания файла: $fileUrl');

      if (kIsWeb) {
        // Для веб-версии используем window.open
        html.window.open(fileUrl, '_blank');
        
        // Показываем уведомление об успешном начале скачивания
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Файл скачивается...'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        // Для мобильных устройств
        // Запрашиваем разрешение на сохранение файлов
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
          if (!status.isGranted) {
            throw Exception('Необходимо разрешение на сохранение файлов');
          }
        }

        // Получаем директорию для загрузок
        final directory = await getApplicationDocumentsDirectory();
        final fileName = fileUrl.split('/').last;
        final filePath = '${directory.path}/$fileName';

        print('Сохранение в: $filePath');

        try {
          await _dio.download(
            fileUrl,
            filePath,
            onReceiveProgress: (received, total) {
              if (total != -1) {
                print('Прогресс: ${(received / total * 100).toStringAsFixed(0)}%');
              }
            },
          );

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Файл успешно скачан'),
                action: SnackBarAction(
                  label: 'Открыть',
                  onPressed: () async {
                    try {
                      await Share.shareXFiles([XFile(filePath)]);
                    } catch (e) {
                      print('Ошибка при открытии файла: $e');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Ошибка при открытии файла: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
                duration: const Duration(seconds: 5),
              ),
            );
          }
        } on DioException catch (e) {
          print('Ошибка DIO при скачивании: $e');
          print('Статус ответа: ${e.response?.statusCode}');
          print('Данные ответа: ${e.response?.data}');
          throw Exception('Ошибка при скачивании файла: ${e.message}');
        }
      }
    } catch (e) {
      print('Ошибка при скачивании документа: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при скачивании: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Удаление документа
  Future<bool> deleteDocument(int documentId) async {
    try {
      print('Удаление документа с ID: $documentId');
      
      // Проверяем валидность ID
      if (documentId <= 0) {
        print('Некорректный ID документа: $documentId');
        return false;
      }

      // Формируем URL для удаления
      final endpoint = 'documents/$documentId/';  // Добавляем слэш в конце
      print('Отправка DELETE запроса на endpoint: $endpoint');

      final response = await _apiService.deleteData(endpoint);
      
      print('Полный ответ сервера: $response');
      
      // Расширенная проверка ответа
      if (response != null) {
        if (response['success'] == true || 
            response['status'] == 'success' || 
            response['deleted'] == true) {
          print('Документ успешно удален');
          return true;
        } else {
          print('Ошибка удаления. Ответ сервера: $response');
          return false;
        }
      } else {
        print('Пустой ответ от сервера при удалении');
        return false;
      }
    } catch (e, stackTrace) {
      print('Исключение при удалении документа: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  Future<bool> uploadToGoogleDrive({
    required PlatformFile file,
    required BuildContext context,
  }) async {
    try {
      // Авторизация в Google
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        throw Exception('Не удалось войти в аккаунт Google');
      }

      // Получаем заголовки авторизации
      final authHeaders = await account.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);

      // Создаем API клиент
      final driveApi = drive.DriveApi(authenticateClient);

      // Создаем метаданные файла
      final driveFile = drive.File()
        ..name = file.name
        ..mimeType = 'application/pdf';

      // Загружаем файл
      final media = drive.Media(
        Stream.fromIterable([file.bytes!]),
        file.bytes!.length,
      );

      final result = await driveApi.files.create(
        driveFile,
        uploadMedia: media,
      );

      // Получаем публичную ссылку
      await driveApi.permissions.create(
        drive.Permission()
          ..type = 'anyone'
          ..role = 'reader',
        result.id!,
      );

      final webViewLink = 'https://drive.google.com/file/d/${result.id}/view';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Text('Документ загружен в Google Drive '),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(webViewLink)),
                child: const Text(
                  'Открыть',
                  style: TextStyle(color: Colors.blue),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 10),
        ),
      );

      return true;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при загрузке в Google Drive: $e')),
      );
      return false;
    }
  }
}

// Вспомогательный класс для аутентификации
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}