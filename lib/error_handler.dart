import 'package:flutter/material.dart';
import 'package:flutter/services.dart';  // Для работы с буфером обмена

class ErrorHandler {

  static void showError(
      BuildContext context,
      String message, {
        VoidCallback? onTapAction, // Обработчик нажатия
      }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: GestureDetector(
          onDoubleTap: () {
            Clipboard.setData(ClipboardData(text: message));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Текст скопирован!')),
            );
          },
          onTap: onTapAction, // Действие при одиночном нажатии
          child: Text(
            message,
            style: const TextStyle(color: Colors.white),
          ),
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
        showCloseIcon: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  static void showInfo(
      BuildContext context,
      String message, {
        VoidCallback? onTapAction, // Обработчик нажатия
      }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: GestureDetector(
          onDoubleTap: () {
            // Копирование текста в буфер обмена
            Clipboard.setData(ClipboardData(text: message));
            // Показать сообщение, что текст скопирован
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Текст скопирован!')),
            );
          },
          onTap: onTapAction, // Действие при одиночном нажатии
          child: Text(
            message,
            style: const TextStyle(color: Colors.white),
          ),
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  static void handleError(BuildContext context, Object error, StackTrace? stackTrace) {
    final errorMessage = error.toString();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: GestureDetector(
          onDoubleTap: () {
            // Копирование текста ошибки в буфер обмена
            Clipboard.setData(ClipboardData(text: errorMessage));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ошибка скопирована!')),
            );
          },
          child: Text(
            'Ошибка: $errorMessage',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
    debugPrint('Error: $error');
    debugPrint('StackTrace: $stackTrace');
  }

}

void runAppErrorHandling({
  BuildContext? context,
  required Object error,
  StackTrace? stackTrace,
}) {
  if (context != null) {
    ErrorHandler.handleError(context, error, stackTrace);
  } else {
  }
}

