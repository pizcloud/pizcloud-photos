import 'package:http/http.dart' as http;
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';

enum InstructionFeature { backup, referral, share, transferOwnership }

extension InstructionFeatureApi on InstructionFeature {
  String get apiSegment => switch (this) {
    InstructionFeature.backup => 'backup',
    InstructionFeature.referral => 'referral',
    InstructionFeature.share => 'share',
    InstructionFeature.transferOwnership => 'transfer-ownership',
  };
}

class InstructionSlide {
  const InstructionSlide({required this.imageUrl, this.caption});

  final String imageUrl;
  final String? caption;
}

class InstructionContentService {
  const InstructionContentService({
    this.apiBaseUrl,
    this.imageRootPath = '/images/instructions',
    this.imageFileExtension = 'jpg',
    this.maxSlidesPerFeature = 30,
    this.requestTimeout = const Duration(seconds: 4),
    this.httpClient,
  });

  final String? apiBaseUrl;
  final String imageRootPath;
  final String imageFileExtension;
  final int maxSlidesPerFeature;
  final Duration requestTimeout;
  final http.Client? httpClient;

  Future<List<InstructionSlide>> fetchSlides({required InstructionFeature feature, String? languageCode}) async {
    final baseUri = _resolveBaseUri();
    if (baseUri == null) {
      return _fallbackSlides[feature] ?? const [];
    }

    final client = httpClient ?? http.Client();
    final shouldCloseClient = httpClient == null;

    try {
      final primaryLanguageFolder = _resolveLanguageFolder(languageCode);
      final languageFolders = <String>[primaryLanguageFolder, if (primaryLanguageFolder != 'en') 'en'];

      for (final languageFolder in languageFolders) {
        final slides = await _collectSlides(
          baseUri: baseUri,
          feature: feature,
          languageFolder: languageFolder,
          client: client,
        );
        if (slides.isNotEmpty) {
          return slides;
        }
      }

      return const <InstructionSlide>[];
    } finally {
      if (shouldCloseClient) {
        client.close();
      }
    }
  }

  Uri? _resolveBaseUri() {
    final fromStore = Store.tryGet<String>(StoreKey.serverUrl);
    final candidate = (apiBaseUrl ?? fromStore)?.trim();
    if (candidate == null || candidate.isEmpty) {
      return null;
    }

    final baseUri = Uri.tryParse(candidate);
    if (baseUri == null || baseUri.host.isEmpty) {
      return null;
    }
    return baseUri;
  }

  String _resolveLanguageFolder(String? languageCode) {
    final normalizedCode = languageCode?.trim().toLowerCase();
    if (normalizedCode != null && normalizedCode.startsWith('vi')) {
      return 'vi';
    }
    return 'en';
  }

  Future<List<InstructionSlide>> _collectSlides({
    required Uri baseUri,
    required InstructionFeature feature,
    required String languageFolder,
    required http.Client client,
  }) async {
    final slides = <InstructionSlide>[];
    var foundAtLeastOne = false;

    final maxSlides = maxSlidesPerFeature < 1 ? 1 : maxSlidesPerFeature;
    for (var index = 1; index <= maxSlides; index++) {
      final slideUri = _buildSlideUri(baseUri: baseUri, feature: feature, languageFolder: languageFolder, index: index);
      final exists = await _resourceExists(uri: slideUri, client: client);

      if (!exists) {
        if (foundAtLeastOne) {
          break;
        }
        continue;
      }

      foundAtLeastOne = true;
      slides.add(InstructionSlide(imageUrl: slideUri.toString()));
    }

    return slides;
  }

  Uri _buildSlideUri({
    required Uri baseUri,
    required InstructionFeature feature,
    required String languageFolder,
    required int index,
  }) {
    final baseSegments = baseUri.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
    final normalizedRootPath = imageRootPath.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final rootSegments = normalizedRootPath.isEmpty
        ? const <String>[]
        : normalizedRootPath.split('/').where((segment) => segment.isNotEmpty).toList(growable: false);
    final extension = imageFileExtension.trim().replaceAll('.', '');

    return baseUri.replace(
      pathSegments: [...baseSegments, ...rootSegments, feature.apiSegment, languageFolder, '$index.$extension'],
    );
  }

  Future<bool> _resourceExists({required Uri uri, required http.Client client}) async {
    try {
      final headResponse = await client.head(uri).timeout(requestTimeout);
      if (_isSuccessStatus(headResponse.statusCode)) {
        return true;
      }

      // Some setups disable HEAD. Fallback to a tiny range GET.
      if (headResponse.statusCode != 405) {
        return false;
      }

      final getResponse = await client.get(uri, headers: const {'Range': 'bytes=0-0'}).timeout(requestTimeout);
      return _isSuccessStatus(getResponse.statusCode) || getResponse.statusCode == 206;
    } catch (_) {
      return false;
    }
  }

  bool _isSuccessStatus(int statusCode) {
    return statusCode >= 200 && statusCode < 300;
  }

  static const Map<InstructionFeature, List<InstructionSlide>> _fallbackSlides = {
    InstructionFeature.backup: <InstructionSlide>[],
    InstructionFeature.referral: <InstructionSlide>[],
    InstructionFeature.share: <InstructionSlide>[],
    InstructionFeature.transferOwnership: <InstructionSlide>[],
  };
}
