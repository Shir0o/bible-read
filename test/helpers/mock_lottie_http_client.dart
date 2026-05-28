import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mocktail/mocktail.dart';

/// Overrides HTTP requests to return a minimal Lottie JSON.
void setupLottieHttpOverrides() {
  HttpOverrides.global = _LottieHttpOverrides();
}

/// Resets any global [HttpOverrides].
void resetHttpOverrides() {
  HttpOverrides.global = null;
}

class _LottieHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
}

class _MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpClientResponse extends Fake implements HttpClientResponse {
  final Uint8List _body = Uint8List.fromList(
    utf8.encode(
      '{"v":"5.7.6","fr":30,"ip":0,"op":30,"w":100,"h":100,"nm":"empty","ddd":0,"assets":[],"layers":[]}',
    ),
  );

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _body.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_body]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class _MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}
