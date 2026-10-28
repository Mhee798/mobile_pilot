import 'dart:io';

class ModelDownloadProgress {
  const ModelDownloadProgress(this.received, this.total, this.elapsed);

  final int received;
  final int? total;
  final Duration elapsed;

  double? get bytesPerSecond => elapsed.inMilliseconds > 0
      ? received * 1000 / elapsed.inMilliseconds
      : null;
}

class ModelDownload {
  final HttpClient _client = HttpClient()..autoUncompress = false;
  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _client.close(force: true);
  }

  Future<void> download(
    Uri url,
    File destination,
    void Function(ModelDownloadProgress progress) onProgress,
  ) async {
    final elapsed = Stopwatch()..start();
    IOSink? sink;
    try {
      final request = await _client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      final total = response.contentLength >= 0 ? response.contentLength : null;
      var received = 0;
      sink = destination.openWrite();
      onProgress(ModelDownloadProgress(0, total, elapsed.elapsed));
      await sink.addStream(
        response.map((chunk) {
          if (_cancelled) throw const HttpException('Download cancelled');
          received += chunk.length;
          onProgress(ModelDownloadProgress(received, total, elapsed.elapsed));
          return chunk;
        }),
      );
      await sink.flush();
      if (_cancelled) throw const HttpException('Download cancelled');
      if (total != null && received != total) {
        throw const HttpException('Download incomplete');
      }
    } finally {
      await sink?.close();
      _client.close(force: true);
    }
  }
}

String formatDownloadSize(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1000 && unit < units.length - 1) {
    size /= 1000;
    unit++;
  }
  return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}
