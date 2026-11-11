import 'package:dio/dio.dart';

class BmstuAuthException implements Exception {
  final String message;
  BmstuAuthException([this.message = 'Сессия устарела или требуется повторная авторизация']);
  @override
  String toString() => message;
}

// Transport-level failure (no network, timeout, server down) as opposed to bad credentials
class BmstuNetworkException implements Exception {
  final String message;
  BmstuNetworkException(this.message);

  factory BmstuNetworkException.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return BmstuNetworkException('Сервер МГТУ не отвечает. Попробуйте позже');
      case DioExceptionType.badCertificate:
        return BmstuNetworkException('Не удалось установить защищённое соединение с сервером МГТУ');
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        return BmstuNetworkException('Сервер МГТУ временно недоступен${code != null ? ' (код $code)' : ''}');
      case DioExceptionType.cancel:
        return BmstuNetworkException('Запрос к серверу МГТУ был отменён');
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return BmstuNetworkException('Нет подключения к серверу МГТУ. Проверьте интернет');
    }
  }

  @override
  String toString() => message;
}
