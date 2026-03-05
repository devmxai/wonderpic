import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class BackendApiException implements Exception {
  BackendApiException({
    required this.message,
    required this.statusCode,
    this.payload,
  });

  final String message;
  final int statusCode;
  final Map<String, dynamic>? payload;

  @override
  String toString() =>
      'BackendApiException(statusCode: $statusCode, message: $message)';
}

class WonderPicBackendClient {
  WonderPicBackendClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  static const String _defaultSupabaseUrl =
      'https://pamlemagzhikexxmaxfz.supabase.co';
  static const String _supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _defaultSupabaseUrl,
  );

  static const String _supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: ''),
  );

  final http.Client _httpClient;

  bool get isConfigured {
    final String raw = _supabaseUrl.trim();
    if (raw.isEmpty) return false;
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return false;
    }
    final String scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  void dispose() {
    _httpClient.close();
  }

  Future<Map<String, dynamic>> syncAccountSession() async {
    final Map<String, dynamic> response = await _postFunction(
      functionName: 'account-session',
      body: const <String, dynamic>{},
    );
    return (response['account'] as Map?)?.cast<String, dynamic>() ?? response;
  }

  Future<Map<String, dynamic>> getAccountStatus() async {
    final Map<String, dynamic> response = await _postFunction(
      functionName: 'account-status',
      body: const <String, dynamic>{'action': 'get'},
    );
    return (response['result'] as Map?)?.cast<String, dynamic>() ?? response;
  }

  Future<Map<String, dynamic>> reserveCredits({
    required double amount,
    required String idempotencyKey,
    required String operationKey,
    String? reason,
    int ttlSeconds = 900,
    Map<String, dynamic>? metadata,
  }) async {
    final Map<String, dynamic> response = await _postFunction(
      functionName: 'credits-reserve',
      idempotencyKey: idempotencyKey,
      body: <String, dynamic>{
        'amount': amount,
        'idempotencyKey': idempotencyKey,
        'operationKey': operationKey,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        'ttlSeconds': ttlSeconds,
        'metadata': metadata ?? const <String, dynamic>{},
      },
    );
    return (response['result'] as Map?)?.cast<String, dynamic>() ?? response;
  }

  Future<Map<String, dynamic>> commitCredits({
    required String holdId,
    required String idempotencyKey,
    String? reason,
    Map<String, dynamic>? metadata,
  }) async {
    final Map<String, dynamic> response = await _postFunction(
      functionName: 'credits-commit',
      idempotencyKey: idempotencyKey,
      body: <String, dynamic>{
        'holdId': holdId,
        'idempotencyKey': idempotencyKey,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        'metadata': metadata ?? const <String, dynamic>{},
      },
    );
    return (response['result'] as Map?)?.cast<String, dynamic>() ?? response;
  }

  Future<Map<String, dynamic>> refundCredits({
    required String holdId,
    required String idempotencyKey,
    String? reason,
    Map<String, dynamic>? metadata,
  }) async {
    final Map<String, dynamic> response = await _postFunction(
      functionName: 'credits-refund',
      idempotencyKey: idempotencyKey,
      body: <String, dynamic>{
        'holdId': holdId,
        'idempotencyKey': idempotencyKey,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        'metadata': metadata ?? const <String, dynamic>{},
      },
    );
    return (response['result'] as Map?)?.cast<String, dynamic>() ?? response;
  }

  Future<Map<String, dynamic>> consumeFreeTrialAction({
    required String operationType,
    required String idempotencyKey,
    Map<String, dynamic>? metadata,
  }) async {
    final Map<String, dynamic> response = await _postFunction(
      functionName: 'free-trial-consume',
      idempotencyKey: idempotencyKey,
      body: <String, dynamic>{
        'operationType': operationType,
        'idempotencyKey': idempotencyKey,
        'metadata': metadata ?? const <String, dynamic>{},
      },
    );
    return (response['result'] as Map?)?.cast<String, dynamic>() ?? response;
  }

  Future<Map<String, dynamic>> requestDeleteMyAccount({String? reason}) async {
    final Map<String, dynamic> response = await _postFunction(
      functionName: 'account-status',
      body: <String, dynamic>{
        'action': 'delete_me',
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return (response['result'] as Map?)?.cast<String, dynamic>() ?? response;
  }

  Future<Map<String, dynamic>> _postFunction({
    required String functionName,
    required Map<String, dynamic> body,
    String? idempotencyKey,
  }) async {
    if (!isConfigured) {
      throw BackendApiException(
        message:
            'Supabase backend is not configured. Add a valid SUPABASE_URL via --dart-define.',
        statusCode: 500,
      );
    }

    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw BackendApiException(
        message: 'User is not authenticated in Firebase.',
        statusCode: 401,
      );
    }

    final String idToken = (await currentUser.getIdToken())?.trim() ?? '';
    if (idToken.isEmpty) {
      throw BackendApiException(
        message: 'Firebase ID token is missing.',
        statusCode: 401,
      );
    }
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
    };
    final String publishable = _supabasePublishableKey.trim();
    if (publishable.isNotEmpty) {
      headers['apikey'] = publishable;
    }

    final String idem = idempotencyKey?.trim() ?? '';
    if (idem.isNotEmpty) {
      headers['x-idempotency-key'] = idem;
    }

    final Uri uri = Uri.parse('$_supabaseUrl/functions/v1/$functionName');

    final http.Response response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );

    Map<String, dynamic> decoded = <String, dynamic>{};
    if (response.body.trim().isNotEmpty) {
      final Object? parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) {
        decoded = parsed;
      }
    }

    final bool okFlag = decoded['ok'] is bool ? decoded['ok'] as bool : true;
    if (response.statusCode < 200 || response.statusCode >= 300 || !okFlag) {
      final String message =
          (decoded['error']?.toString().trim().isNotEmpty ?? false)
              ? decoded['error'].toString()
              : 'Backend request failed (${response.statusCode}).';
      throw BackendApiException(
        message: message,
        statusCode: response.statusCode,
        payload: decoded,
      );
    }

    return decoded;
  }
}
