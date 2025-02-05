// ignore_for_file: use_build_context_synchronously, avoid_print, depend_on_referenced_packages

import 'dart:core';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import "package:http_parser/http_parser.dart";
import 'error_handler.dart';
import 'dart:convert';
import 'api.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
class ApiService {

  final String baseUrl = api;
  final Dio _dio = Dio(BaseOptions(baseUrl: "$api/"));
  // final String baseUrl;
  // final Dio _dio;

  ApiService({String? baseUrl, Dio? dio});
  Future<dynamic> putDataFormData(BuildContext context,String path, FormData formData) async {
    try {
      final response = await _dio.put(
        path,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      return response.data;

    } catch (e) {
      ErrorHandler.showError(context, 'Ошибка при измении изображения');
      return null;
    }
  }

  Future<dynamic> postDataFormData(BuildContext context,String endpoint, FormData formData) async
  {
    try
    {
      final response = await _dio.post(
        endpoint, data: formData, options: Options(contentType: "multipart/form-data")
      );
      return response.data;
    }
    catch(e)
    {
      ErrorHandler.showError(context, e.toString());
      return null;
    }
  }

  // Future<String?> checkCurrentUserStatus() async {
  //   String? accessToken = await getAccessToken();

  //   if (accessToken == null) {
  //     String? refreshToken = await getRefreshToken();
  //     if (refreshToken != null) {
  //       String? newAccessToken = await refreshAccessToken(refreshToken);
  //       if (newAccessToken != null) {
  //         await setAccessToken(newAccessToken);
  //         return newAccessToken;
  //       } else {
  //         //Log
  //         return null;
  //       }
  //     }
  //   }
  //   return accessToken;
  // }

  // Future<void> checkAuthUser(BuildContext context) async {
  //   String? token = await getAccessToken();
  //   if (token == null) {
  //     Navigator.pushReplacementNamed(context, '/login');
  //   }
  // }

  // Future<bool> isTokenValid(String token) async {
  //   final response = await http.get(
  //     Uri.parse("$baseUrl/api/"),
  //     headers: {"Authorization": "Bearer $token"},
  //   );
  //   return response.statusCode != 401;
  // }

  // Future<String?> getAccessToken() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   return prefs.getString('accessToken');
  // }

  // Future<void> logout(BuildContext context) async {
  //   final prefs = await SharedPreferences.getInstance();
  //   await prefs.remove('accessToken');
  //   await prefs.remove('refreshToken');
  //   ErrorHandler.showInfo(context, "Пользователь вышел с аккаунта");
  //   Navigator.pushNamed(context, "/");
  // }

  // Future<String?> getRefreshToken() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   return prefs.getString('refreshToken');
  // }

  // Future<String?> refreshAccessToken(String refreshToken) async {
  //   final response = await http.post(
  //     Uri.parse("$baseUrl/api/token/refresh/"),
  //     headers: {"Content-Type": "application/json"},
  //     body: json.encode({'refresh': refreshToken}),
  //   );

  //   if (response.statusCode == 200) {
  //     final data = json.decode(response.body);
  //     return data['access'];
  //   } else {
  //     print("Ошибка обновления токена: ${response.statusCode}");
  //     return null;
  //   }
  // }

  // Future<void> setAccessToken(String accessToken) async {
  //   final prefs = await SharedPreferences.getInstance();
  //   await prefs.setString('accessToken', accessToken);
  // }
  // Future<Map<String, dynamic>?> patchData(String endpoint, bool auth, Map<String,dynamic> data, dynamic context, String message, String errorMessage) async
  // {
  //   final token = auth? await checkCurrentUserStatus(): null;
  //   Map<String, String> headers = {
  //     "Content-Type": "application/json",
  //   };

  //   if (auth && token != null) {
  //     headers["Authorization"] = "Bearer $token";
  //   }
  //   final response = await http.patch(
  //   Uri.parse("$baseUrl/$endpoint"),
  // headers: headers,
  // body: json.encode(data),
  //   );
  //   if (response.statusCode == 200 || response.statusCode == 201) {
  //     ErrorHandler.showInfo(context, message);
  //     return json.decode(response.body);
  //   } else {
  //     ErrorHandler.showError(context, errorMessage);
  //     return null;
  //   }

  // }
  Future<Map<String, dynamic>?> putData(bool auth,
      String endpoint, Map<String, dynamic> data, dynamic context, String message, String errormessage) async {
    Map<String, String> headers = {
      "Content-Type": "application/json",
    };

    
    final response = await http.put(
      Uri.parse("$baseUrl/$endpoint"),
      headers: headers,
      body: json.encode(data),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      ErrorHandler.showInfo(context, message);
      return json.decode(response.body);
    } else {
      ErrorHandler.showError(context, errormessage);
      return null;
    }
  }
  Future<String?> putDataImage(String endpoint, PlatformFile? file, BuildContext context) async {
    if (file == null) {
      ErrorHandler.showError(context, "Файл не найден");
      return null;
    }

    try {
      var avatarBytes = file.bytes;
      var fileExtension = file.name.split('.').last.toLowerCase();

      String mimeType;
      switch (fileExtension) {
        case 'jpg':
        case 'jpeg':
          mimeType = 'image/jpeg';
          break;
        case 'png':
          mimeType = 'image/png';
          break;
        case 'webp':
          mimeType = 'image/webp';
          break;
        case 'gif':
          mimeType = 'image/gif';
          break;
        default:
          mimeType = 'application/octet-stream';
      }

      var request = http.MultipartRequest("PUT", Uri.parse("$baseUrl/$endpoint"));
      request.files.add(http.MultipartFile.fromBytes(
          "file",
          avatarBytes!,
          filename: file.name,
          contentType: MediaType.parse(mimeType)
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        var responseData = json.decode(response.body);
        return responseData["file_url"];
      } else {
        print("Error uploading image: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("Error uploading image: $e");
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getDataList(String endpoint, bool auth) async {
    Map<String, String> headers = {"Content-Type":"application/json"};
    
    final url = Uri.parse('$baseUrl/$endpoint');
    final response = await http.get(url, headers: headers);
    if (response.statusCode == 200) {
      List<dynamic> jsonResponse = jsonDecode(response.body);
      List<Map<String, dynamic>> dataList = jsonResponse.map((item) => item as Map<String, dynamic>).toList();
      return dataList;
    } else {
      throw Exception('Не удалось загрузить данные');
    }
  }

  Future<dynamic> getData(String endpoint) async {
    Map<String, String> headers = {
      "Content-Type": "application/json",
    };


    final response = await http.get(Uri.parse("$baseUrl/$endpoint"), headers: headers);
    if (response.statusCode == 200) {
      // final jsonString = utf8.decode(response.bodyBytes);
      // return json.decode(jsonString);
      return json.decode(response.body);
    } else {
      print("Error in method getData: ${response.statusCode}");
      return null;
    }
  }

    Future<Map<String, dynamic>?> postData(
        String endpoint, Map<String, dynamic> data,  String methodName, String message, [BuildContext? context]) async {
      Map<String, String> headers = {"Content-Type":"application/json"};
      
      final response = await http.post(
        Uri.parse('$baseUrl/$endpoint'),
        headers: headers,
        body: json.encode(data),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        if(context != null) {
          ErrorHandler.showInfo(context, message);
        }
        return json.decode(response.body);
      } else {
        return null;
      }
    }
  Future<void> delData(String endpoint) async
  {
    Map<String, String> headers = {"Content-Type":"application/json"};
    
    http.delete(Uri.parse("$baseUrl/$endpoint"), headers: headers);
  }

  // Future<Map<String, dynamic>?> getUserData(String endpoint) async {

  //   final response = await http.get(
  //     Uri.parse("$baseUrl/$endpoint"),
  //     headers: {"Authorization": "Bearer $token"},
  //   );

  //   if (response.statusCode == 200) {
  //     return json.decode(response.body);
  //   } else {
  //     return null;
  //   }
  // }


//   Future<void> registerUser({
//     required String username,
//     required String email,
//     required String password,
//     required dynamic context,
//     required bool business,
//   }) async {
//     print("Registering with business: $business");
//     final data = await postData('register/', {
//       'name': username,
//       'email': email,
//       'password': password,
//       'business_account': business
//     }, false, "registerUser", "Успешный вход", context);
//     if (data != null) {
//       final accessToken = data["access"];
//       await setAccessToken(accessToken);
//       if (business) {
//         Navigator.pushReplacementNamed(context, '/registerHotel');
//       }
//       else{
//       Navigator.pushReplacementNamed(context, '/');}
//     }
//   }

  Future<Map<String, dynamic>?> deleteData(String endpoint) async {
    try {
      final url = Uri.parse('$baseUrl/$endpoint');
      print('DELETE запрос на URL: $url');

      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          // Добавьте другие необходимые заголовки
        },
      );

      print('DELETE response status: ${response.statusCode}');
      print('DELETE response headers: ${response.headers}');
      print('DELETE response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (response.body.isEmpty) {
          return {'success': true};
        }
        return jsonDecode(response.body);
      } else {
        print('Ошибка при удалении. Статус: ${response.statusCode}');
        print('Тело ответа: ${response.body}');
        
        // Пытаемся распарсить тело ошибки
        if (response.body.isNotEmpty) {
          try {
            return jsonDecode(response.body);
          } catch (e) {
            print('Ошибка парсинга тела ответа: $e');
          }
        }
        return {'success': false, 'error': 'HTTP ${response.statusCode}'};
      }
    } catch (e, stackTrace) {
      print('Исключение при удалении: $e');
      print('Stack trace: $stackTrace');
      return {'success': false, 'error': e.toString()};
    }
  }
}