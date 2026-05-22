/// Data-layer exception classes
class ServerException implements Exception {
  final String message;
  const ServerException(this.message);

  @override
  String toString() => 'ServerException: $message';
}

class AppAuthException implements Exception {
  final String message;
  const AppAuthException(this.message);

  @override
  String toString() => 'AppAuthException: $message';
}

class CacheException implements Exception {
  final String message;
  const CacheException(this.message);

  @override
  String toString() => 'CacheException: $message';
}
