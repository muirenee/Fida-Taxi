final class FidaApiException implements Exception {
  const FidaApiException({
    required this.message,
    this.statusCode,
    this.error,
    this.details,
  });

  final String message;
  final int? statusCode;
  final String? error;
  final Object? details;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' HTTP $statusCode';
    final category = error == null ? '' : ' [$error]';

    return 'FidaApiException$status$category: $message';
  }
}
