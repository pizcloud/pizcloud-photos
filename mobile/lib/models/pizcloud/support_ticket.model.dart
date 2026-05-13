class SupportTicketAttachment {
  const SupportTicketAttachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.url,
    this.createdAt,
  });

  final String id;
  final String fileName;
  final String mimeType;
  final int size;
  final String url;
  final DateTime? createdAt;

  factory SupportTicketAttachment.fromJson(Map<String, dynamic> json) {
    return SupportTicketAttachment(
      id: _asString(json['id']) ?? _asString(json['_id']) ?? '',
      fileName: _asString(json['fileName']) ?? _asString(json['filename']) ?? _asString(json['name']) ?? '',
      mimeType: _asString(json['mimeType']) ?? _asString(json['contentType']) ?? '',
      size: _asInt(json['size']) ?? 0,
      url: _asString(json['url']) ?? '',
      createdAt: _asDateTime(json['createdAt']),
    );
  }
}

class SupportTicketMessage {
  const SupportTicketMessage({
    required this.id,
    required this.ticketId,
    required this.senderType,
    required this.message,
    required this.attachments,
    this.createdAt,
  });

  final String id;
  final String ticketId;
  final String senderType;
  final String message;
  final List<SupportTicketAttachment> attachments;
  final DateTime? createdAt;

  factory SupportTicketMessage.fromJson(Map<String, dynamic> json) {
    final attachmentsRaw = json['attachments'];
    final attachments = <SupportTicketAttachment>[];

    if (attachmentsRaw is List) {
      for (final item in attachmentsRaw) {
        if (item is Map<String, dynamic>) {
          attachments.add(SupportTicketAttachment.fromJson(item));
        }
      }
    }

    return SupportTicketMessage(
      id: _asString(json['id']) ?? _asString(json['_id']) ?? '',
      ticketId: _asString(json['ticketId']) ?? '',
      senderType: _asString(json['senderType']) ?? _asString(json['role']) ?? 'user',
      message: _asString(json['message']) ?? '',
      attachments: attachments,
      createdAt: _asDateTime(json['createdAt']),
    );
  }
}

class SupportTicketItem {
  const SupportTicketItem({
    required this.id,
    required this.subject,
    required this.category,
    required this.priority,
    required this.status,
    required this.latestMessage,
    required this.unreadCount,
    required this.attachments,
    this.createdAt,
    this.updatedAt,
    this.closedAt,
  });

  final String id;
  final String subject;
  final String category;
  final String priority;
  final String status;
  final String latestMessage;
  final int unreadCount;
  final List<SupportTicketAttachment> attachments;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? closedAt;

  factory SupportTicketItem.fromJson(Map<String, dynamic> json) {
    final attachmentsRaw = json['attachments'];
    final attachments = <SupportTicketAttachment>[];

    if (attachmentsRaw is List) {
      for (final item in attachmentsRaw) {
        if (item is Map<String, dynamic>) {
          attachments.add(SupportTicketAttachment.fromJson(item));
        }
      }
    }

    return SupportTicketItem(
      id: _asString(json['id']) ?? _asString(json['_id']) ?? '',
      subject: _asString(json['subject']) ?? '',
      category: _asString(json['category']) ?? 'other',
      priority: _asString(json['priority']) ?? 'normal',
      status: _asString(json['status']) ?? 'open',
      latestMessage: _asString(json['latestMessage']) ?? _asString(json['message']) ?? '',
      unreadCount: _asInt(json['unreadCount']) ?? 0,
      attachments: attachments,
      createdAt: _asDateTime(json['createdAt']),
      updatedAt: _asDateTime(json['updatedAt']),
      closedAt: _asDateTime(json['closedAt']),
    );
  }
}

class SupportTicketDetail {
  const SupportTicketDetail({required this.ticket, required this.messages});

  final SupportTicketItem ticket;
  final List<SupportTicketMessage> messages;

  factory SupportTicketDetail.fromJson(Map<String, dynamic> json) {
    final ticketRaw = json['ticket'];
    final ticket = ticketRaw is Map<String, dynamic>
        ? SupportTicketItem.fromJson(ticketRaw)
        : SupportTicketItem.fromJson(json);

    final messagesRaw = json['messages'];
    final messages = <SupportTicketMessage>[];

    if (messagesRaw is List) {
      for (final item in messagesRaw) {
        if (item is Map<String, dynamic>) {
          messages.add(SupportTicketMessage.fromJson(item));
        }
      }
    }

    return SupportTicketDetail(ticket: ticket, messages: messages);
  }
}

class SupportTicketListResponse {
  const SupportTicketListResponse({required this.items, required this.page, required this.limit, required this.total});

  final List<SupportTicketItem> items;
  final int page;
  final int limit;
  final int total;

  factory SupportTicketListResponse.empty({int page = 1, int limit = 20}) {
    return SupportTicketListResponse(items: const <SupportTicketItem>[], page: page, limit: limit, total: 0);
  }
}

String? _asString(dynamic value) {
  if (value == null) {
    return null;
  }

  final normalized = value.toString().trim();
  if (normalized.isEmpty) {
    return null;
  }

  return normalized;
}

int? _asInt(dynamic value) {
  if (value is num) {
    return value.toInt();
  }

  if (value is String) {
    return int.tryParse(value.trim());
  }

  return null;
}

DateTime? _asDateTime(dynamic value) {
  final raw = _asString(value);
  if (raw == null) {
    return null;
  }

  try {
    return DateTime.parse(raw);
  } catch (_) {
    return null;
  }
}
