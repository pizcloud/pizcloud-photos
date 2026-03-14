// new
typedef PizGalleryHeadersResolver = Map<String, String> Function();

/// Global auth context for network requests inside pizcloud_gallery.
///
/// Host apps can set [configure] before rendering the gallery.
class PizGalleryAuthContext {
  PizGalleryAuthContext._();

  static PizGalleryHeadersResolver? _headersResolver;

  static void configure({PizGalleryHeadersResolver? headersResolver}) {
    _headersResolver = headersResolver;
  }

  static void clear() {
    _headersResolver = null;
  }

  static Map<String, String>? resolveHeaders() {
    final resolver = _headersResolver;
    if (resolver == null) {
      return null;
    }

    final headers = resolver();
    if (headers.isEmpty) {
      return null;
    }

    return Map<String, String>.from(headers);
  }

  static Map<String, String>? mergeHeaders([Map<String, String>? headers]) {
    final base = resolveHeaders();
    final custom = headers;

    if ((base == null || base.isEmpty) && (custom == null || custom.isEmpty)) {
      return null;
    }

    final merged = <String, String>{};
    if (base != null && base.isNotEmpty) {
      merged.addAll(base);
    }
    if (custom != null && custom.isNotEmpty) {
      merged.addAll(custom);
    }

    return merged;
  }
}
// #new