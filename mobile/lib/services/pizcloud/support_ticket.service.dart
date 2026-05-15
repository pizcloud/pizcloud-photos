import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:immich_mobile/models/pizcloud/support_ticket.model.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as piz_persist;
import 'package:immich_mobile/services/pizcloud/pizcloud_base_url.service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;

class SupportTicketApiException implements Exception {
  const SupportTicketApiException({required this.message, this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() {
    final status = statusCode;
    if (status == null) {
      return 'SupportTicketApiException: $message';
    }
    return 'SupportTicketApiException($status): $message';
  }
}

class SupportTicketService {
  SupportTicketService({PizcloudBaseUrlService? baseUrlService})
    : _baseUrlService = baseUrlService ?? PizcloudBaseUrlService();

  static const int maxAttachmentBytes = 8 * 1024 * 1024;

  final PizcloudBaseUrlService _baseUrlService;
  late final Future<piz_persist.ApiPersistCookieJarService> _pizApiService = _initPizApiService();

  Future<piz_persist.ApiPersistCookieJarService> _initPizApiService() async {
    final baseUrl = await _baseUrlService.resolveBaseUrl();
    return piz_persist.ApiPersistCookieJarService.instance(baseUrl: baseUrl);
  }

  Future<SupportTicketListResponse> fetchTickets({int page = 1, int limit = 20, String? status}) async {
    final safePage = page < 1 ? 1 : page;
    final safeLimit = limit.clamp(1, 100).toInt();

    final api = await _pizApiService;
    final response = await api.client.get<dynamic>(
      '/support/tickets',
      queryParameters: <String, dynamic>{
        'page': safePage,
        'limit': safeLimit,
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
      },
    );

    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw _toException(response, fallbackMessage: 'Failed to load support tickets');
    }

    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw const SupportTicketApiException(message: 'Invalid support ticket list payload');
    }

    final itemsRaw = body['items'];
    final items = <SupportTicketItem>[];
    if (itemsRaw is List) {
      for (final item in itemsRaw) {
        if (item is Map<String, dynamic>) {
          items.add(SupportTicketItem.fromJson(item));
        }
      }
    }

    final paginationRaw = body['pagination'];
    final pagination = paginationRaw is Map<String, dynamic> ? paginationRaw : const <String, dynamic>{};

    return SupportTicketListResponse(
      items: items,
      page: (pagination['page'] as num?)?.toInt() ?? safePage,
      limit: (pagination['limit'] as num?)?.toInt() ?? safeLimit,
      total: (pagination['total'] as num?)?.toInt() ?? items.length,
    );
  }

  Future<SupportTicketDetail> fetchTicketDetail(String ticketId) async {
    final normalizedTicketId = ticketId.trim();
    if (normalizedTicketId.isEmpty) {
      throw const SupportTicketApiException(message: 'Ticket ID is required');
    }

    final api = await _pizApiService;
    final response = await api.client.get<dynamic>('/support/tickets/${Uri.encodeComponent(normalizedTicketId)}');

    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw _toException(response, fallbackMessage: 'Failed to load support ticket details');
    }

    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw const SupportTicketApiException(message: 'Invalid support ticket details payload');
    }

    return SupportTicketDetail.fromJson(body);
  }

  Future<Uint8List> fetchAttachmentBytes(String attachmentUrl) async {
    final normalizedAttachmentUrl = attachmentUrl.trim();
    if (normalizedAttachmentUrl.isEmpty) {
      throw const SupportTicketApiException(message: 'Attachment URL is required');
    }

    final api = await _pizApiService;
    final resolvedUri = _resolveAttachmentUri(baseUrl: api.baseUrl, attachmentUrl: normalizedAttachmentUrl);
    Response<dynamic> response;
    try {
      response = await api.client.getUri<dynamic>(
        resolvedUri,
        options: Options(
          responseType: ResponseType.bytes,
          headers: const <String, dynamic>{'Accept': '*/*'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );
    } on DioException catch (error) {
      final errorResponse = error.response;
      if (errorResponse != null) {
        throw _toException(errorResponse, fallbackMessage: 'Failed to download support attachment');
      }
      throw SupportTicketApiException(
        message: error.message ?? 'Failed to download support attachment',
        statusCode: error.response?.statusCode,
      );
    }

    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw _toException(response, fallbackMessage: 'Failed to download support attachment');
    }

    final data = response.data;
    if (data is Uint8List) {
      return data;
    }
    if (data is List<int>) {
      return Uint8List.fromList(data);
    }

    throw const SupportTicketApiException(message: 'Invalid support attachment payload');
  }

  Future<SupportTicketDetail> createTicket({
    required String subject,
    required String category,
    required String priority,
    required String message,
    List<String> attachmentPaths = const <String>[],
  }) async {
    final normalizedSubject = subject.trim();
    final normalizedMessage = message.trim();

    if (normalizedSubject.isEmpty) {
      throw const SupportTicketApiException(message: 'Subject is required', code: 'SUBJECT_REQUIRED');
    }

    if (normalizedMessage.isEmpty) {
      throw const SupportTicketApiException(message: 'Message is required', code: 'MESSAGE_REQUIRED');
    }

    final validatedPaths = await _validateAttachmentPaths(attachmentPaths);

    final api = await _pizApiService;
    final payload = await _createMultipartForm(
      category: category,
      priority: priority,
      subject: normalizedSubject,
      message: normalizedMessage,
      attachmentPaths: validatedPaths,
    );

    final response = await api.client.post<dynamic>(
      '/support/tickets',
      data: payload,
      options: Options(contentType: 'multipart/form-data'),
    );

    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw _toException(response, fallbackMessage: 'Failed to create support ticket');
    }

    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw const SupportTicketApiException(message: 'Invalid support ticket create payload');
    }

    return SupportTicketDetail.fromJson(body);
  }

  Future<SupportTicketDetail> replyTicket({
    required String ticketId,
    required String message,
    List<String> attachmentPaths = const <String>[],
  }) async {
    final normalizedTicketId = ticketId.trim();
    final normalizedMessage = message.trim();

    if (normalizedTicketId.isEmpty) {
      throw const SupportTicketApiException(message: 'Ticket ID is required');
    }

    if (normalizedMessage.isEmpty) {
      throw const SupportTicketApiException(message: 'Message is required', code: 'MESSAGE_REQUIRED');
    }

    final validatedPaths = await _validateAttachmentPaths(attachmentPaths);
    final payload = await _createMultipartForm(
      category: 'other',
      priority: 'normal',
      subject: '',
      message: normalizedMessage,
      attachmentPaths: validatedPaths,
      includeTicketMeta: false,
    );

    final api = await _pizApiService;
    final response = await api.client.post<dynamic>(
      '/support/tickets/${Uri.encodeComponent(normalizedTicketId)}/messages',
      data: payload,
      options: Options(contentType: 'multipart/form-data'),
    );

    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw _toException(response, fallbackMessage: 'Failed to reply support ticket');
    }

    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw const SupportTicketApiException(message: 'Invalid support ticket reply payload');
    }

    return SupportTicketDetail.fromJson(body);
  }

  Future<void> updateTicketStatus({required String ticketId, required String status}) async {
    final normalizedTicketId = ticketId.trim();
    final normalizedStatus = status.trim();

    if (normalizedTicketId.isEmpty || normalizedStatus.isEmpty) {
      throw const SupportTicketApiException(message: 'Ticket ID and status are required');
    }

    final api = await _pizApiService;
    final response = await api.client.patch<dynamic>(
      '/support/tickets/${Uri.encodeComponent(normalizedTicketId)}/status',
      data: <String, dynamic>{'status': normalizedStatus},
    );

    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw _toException(response, fallbackMessage: 'Failed to update support ticket status');
    }
  }

  Future<List<String>> _validateAttachmentPaths(List<String> paths) async {
    final normalizedPaths = <String>[];

    for (final item in paths) {
      final normalizedPath = item.trim();
      if (normalizedPath.isEmpty) {
        continue;
      }

      final file = File(normalizedPath);
      if (!await file.exists()) {
        continue;
      }

      final fileLength = await file.length();
      if (fileLength > maxAttachmentBytes) {
        throw const SupportTicketApiException(message: 'Attachment exceeds 8MB limit', code: 'ATTACHMENT_TOO_LARGE');
      }

      normalizedPaths.add(normalizedPath);
    }

    return normalizedPaths;
  }

  Future<FormData> _createMultipartForm({
    required String category,
    required String priority,
    required String subject,
    required String message,
    required List<String> attachmentPaths,
    bool includeTicketMeta = true,
  }) async {
    final fields = <String, dynamic>{
      if (includeTicketMeta) 'subject': subject,
      if (includeTicketMeta) 'category': category.trim().isEmpty ? 'other' : category.trim(),
      if (includeTicketMeta) 'priority': priority.trim().isEmpty ? 'normal' : priority.trim(),
      'message': message,
      'meta': jsonEncode(await _buildClientMeta()),
    };

    final form = FormData.fromMap(fields);

    for (final filePath in attachmentPaths) {
      form.files.add(
        MapEntry('attachments', await MultipartFile.fromFile(filePath, filename: path.basename(filePath))),
      );
    }

    return form;
  }

  Future<Map<String, dynamic>> _buildClientMeta() async {
    String appVersion = '';

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = packageInfo.version.trim();
      final buildNumber = packageInfo.buildNumber.trim();
      if (buildNumber.isNotEmpty) {
        appVersion = '$appVersion+$buildNumber';
      }
    } catch (_) {
      // Keep this best-effort; metadata should never break ticket submission.
    }

    return <String, dynamic>{
      'platform': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      if (appVersion.isNotEmpty) 'appVersion': appVersion,
      'submittedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  SupportTicketApiException _toException(Response<dynamic> response, {required String fallbackMessage}) {
    final statusCode = response.statusCode;
    final payload = _decodeErrorPayload(response.data);

    if (payload != null) {
      final codeRaw = payload['code'];
      final code = codeRaw is String && codeRaw.trim().isNotEmpty ? codeRaw.trim() : null;
      final messageRaw = payload['message'];
      if (messageRaw is String && messageRaw.trim().isNotEmpty) {
        final message = messageRaw.trim();
        return SupportTicketApiException(message: message, code: code ?? message, statusCode: statusCode);
      }

      if (messageRaw is List && messageRaw.isNotEmpty) {
        final first = messageRaw.first;
        if (first is String && first.trim().isNotEmpty) {
          final message = first.trim();
          return SupportTicketApiException(message: message, code: code ?? message, statusCode: statusCode);
        }
      }

      if (code != null) {
        return SupportTicketApiException(message: code, code: code, statusCode: statusCode);
      }
    }

    return SupportTicketApiException(message: fallbackMessage, statusCode: statusCode);
  }
}

final supportTicketService = SupportTicketService();

Uri _resolveAttachmentUri({required String baseUrl, required String attachmentUrl}) {
  final input = attachmentUrl.trim();
  if (input.isEmpty) {
    return Uri.parse(baseUrl);
  }

  final parsedDirect = Uri.tryParse(input);
  if (parsedDirect != null && parsedDirect.hasScheme && parsedDirect.host.isNotEmpty) {
    return parsedDirect;
  }

  final baseUri = Uri.parse(baseUrl);
  final originUri = Uri(scheme: baseUri.scheme, host: baseUri.host, port: baseUri.hasPort ? baseUri.port : null);

  if (input.startsWith('/')) {
    return originUri.resolve(input);
  }

  return baseUri.resolve(input);
}

Map<String, dynamic>? _decodeErrorPayload(dynamic data) {
  if (data is Map<String, dynamic>) {
    return data;
  }

  if (data is Map) {
    final payload = <String, dynamic>{};
    data.forEach((key, value) {
      payload[key.toString()] = value;
    });
    return payload;
  }

  String? text;
  if (data is String) {
    text = data.trim();
  } else if (data is List<int>) {
    text = utf8.decode(data, allowMalformed: true).trim();
  }

  if (text == null || text.isEmpty) {
    return null;
  }

  try {
    final parsed = jsonDecode(text);
    if (parsed is Map<String, dynamic>) {
      return parsed;
    }
    if (parsed is Map) {
      final payload = <String, dynamic>{};
      parsed.forEach((key, value) {
        payload[key.toString()] = value;
      });
      return payload;
    }
  } catch (_) {
    return <String, dynamic>{'message': text};
  }

  return <String, dynamic>{'message': text};
}
