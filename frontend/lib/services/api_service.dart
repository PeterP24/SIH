import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/models.dart';

/// Raised for any backend/network failure so the UI can show a friendly banner.
class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thin REST client for the FastAPI backend.
class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 30);

  Uri _uri(String path, [Map<String, dynamic>? query]) =>
      Uri.parse('${AppConfig.baseUrl}$path').replace(
        queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
      );

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    try {
      final response = await request().timeout(_timeout);
      final body = response.body.isEmpty ? '{}' : jsonDecode(response.body);
      if (response.statusCode >= 400) {
        final detail = body is Map ? body['detail'] : null;
        throw ApiException('HTTP ${response.statusCode}: ${detail ?? response.body}');
      }
      return body;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('Backend timed out (${AppConfig.baseUrl}).');
    } on FormatException {
      throw ApiException('Malformed response from backend.');
    } catch (_) {
      // http.ClientException on web, SocketException on mobile/desktop, plus
      // any other transport failure: all mean the backend is unreachable.
      throw ApiException(
          'Cannot reach backend at ${AppConfig.baseUrl}. Is it running?');
    }
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, dynamic>? query]) async =>
      (await _send(() => _client.get(_uri(path, query)))) as Map<String, dynamic>;

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async =>
      (await _send(() => _client.post(
            _uri(path),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          ))) as Map<String, dynamic>;

  Future<bool> health() async {
    try {
      final data = await _get('/health');
      return data['status'] == 'ok';
    } on ApiException {
      return false;
    }
  }

  Future<SignatureResult> sign(String message, {String signer = 'Alice'}) async =>
      SignatureResult.fromJson(
          await _post('/sign', {'message': message, 'signer': signer}));

  Future<VerificationResult> verify(
    String signatureId, {
    String? message,
    String verifier = 'Bob',
  }) async =>
      VerificationResult.fromJson(await _post('/verify', {
        'signature_id': signatureId,
        'message': ?message,
        'verifier': verifier,
      }));

  Future<AttackResult> simulateAttack(
    String attackType, {
    String? signatureId,
    String? tamperedMessage,
    double channelErrorRate = 0.25,
  }) async =>
      AttackResult.fromJson(await _post('/simulate-attack', {
        'attack_type': attackType,
        'signature_id': ?signatureId,
        if (tamperedMessage != null && tamperedMessage.isNotEmpty)
          'tampered_message': tamperedMessage,
        'channel_error_rate': channelErrorRate,
      }));

  Future<List<AttackType>> attackTypes() async {
    final data = await _send(() => _client.get(_uri('/attack-types'))) as List;
    return data
        .map((e) => AttackType.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<MetricsSnapshot> metrics() async =>
      MetricsSnapshot.fromJson(await _get('/metrics'));

  Future<List<LogEvent>> logs({int limit = 100, String? eventType}) async {
    final data = await _get('/logs', {
      'limit': limit,
      'event_type': ?eventType,
    });
    return (data['events'] as List)
        .map((e) => LogEvent.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<SignatureResult>> signatures({int limit = 50}) async {
    final data = await _get('/signatures', {'limit': limit});
    return (data['signatures'] as List)
        .map((e) => SignatureResult.fromJson({
              ...(e as Map).cast<String, dynamic>(),
              'elapsed_ms': 0,
              'key_qber': 0,
            }))
        .toList();
  }
}
