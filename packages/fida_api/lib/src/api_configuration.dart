final class FidaApiConfiguration {
  FidaApiConfiguration._(this.baseUri);

  final Uri baseUri;

  factory FidaApiConfiguration({required String baseUrl}) {
    final raw = baseUrl.trim();
    final parsed = Uri.tryParse(raw);

    if (parsed == null ||
        !parsed.hasScheme ||
        !parsed.hasAuthority ||
        (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Fida API base URL must be an absolute HTTP(S) URL.',
      );
    }

    if (parsed.hasQuery || parsed.hasFragment) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Fida API base URL cannot contain a query or fragment.',
      );
    }

    final normalizedPath = parsed.path.endsWith('/')
        ? parsed.path
        : '${parsed.path}/';

    return FidaApiConfiguration._(parsed.replace(path: normalizedPath));
  }

  factory FidaApiConfiguration.fromEnvironment() {
    const baseUrl = String.fromEnvironment(
      'FIDA_API_BASE_URL',
      defaultValue: 'http://10.0.2.2:3000/api/v1',
    );

    return FidaApiConfiguration(baseUrl: baseUrl);
  }

  Uri endpoint(String relativePath) {
    final normalized = relativePath.startsWith('/')
        ? relativePath.substring(1)
        : relativePath;

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'Endpoint path cannot be empty.',
      );
    }

    return baseUri.resolve(normalized);
  }
}
