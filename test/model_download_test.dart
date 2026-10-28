import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/data/model_download.dart';

void main() {
  test('downloads bytes and reports real size', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final directory = await Directory.systemTemp.createTemp('model-download-');
    addTearDown(() async {
      await server.close(force: true);
      await directory.delete(recursive: true);
    });
    server.listen((request) async {
      request.response.contentLength = 5;
      request.response.add([1, 2, 3, 4, 5]);
      await request.response.close();
    });
    final file = File('${directory.path}/model.partial');
    final samples = <ModelDownloadProgress>[];
    await ModelDownload().download(
      Uri.parse('http://127.0.0.1:${server.port}/model'),
      file,
      samples.add,
    );
    expect(await file.readAsBytes(), [1, 2, 3, 4, 5]);
    expect(samples.last.received, 5);
    expect(samples.last.total, 5);
    expect(formatDownloadSize(2500000), '2.5 MB');
  });

  test('rejects a failed HTTP response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final directory = await Directory.systemTemp.createTemp('model-download-');
    addTearDown(() async {
      await server.close(force: true);
      await directory.delete(recursive: true);
    });
    server.listen((request) async {
      request.response.statusCode = 404;
      await request.response.close();
    });
    await expectLater(
      ModelDownload().download(
        Uri.parse('http://127.0.0.1:${server.port}/missing'),
        File('${directory.path}/model.partial'),
        (_) {},
      ),
      throwsA(isA<HttpException>()),
    );
  });
}
