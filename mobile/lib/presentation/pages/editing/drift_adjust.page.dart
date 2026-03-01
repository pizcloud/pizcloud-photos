import 'dart:async';
import 'dart:ui' as ui;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/color_filter_generator.dart';

@RoutePage()
class DriftAdjustImagePage extends HookWidget {
  final Image image;
  final BaseAsset asset;

  const DriftAdjustImagePage({super.key, required this.image, required this.asset});

  Future<ui.Image> _createFilteredImage(ui.Image inputImage, ColorFilter filter) {
    final completer = Completer<ui.Image>();
    final size = Size(inputImage.width.toDouble(), inputImage.height.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final paint = Paint()..colorFilter = filter;
    canvas.drawImage(inputImage, Offset.zero, paint);

    recorder.endRecording().toImage(size.width.round(), size.height.round()).then((image) {
      completer.complete(image);
    });

    return completer.future;
  }

  Future<ui.Image> _resolveUiImage(Image sourceImage) async {
    final completer = Completer<ui.Image>();
    sourceImage.image
        .resolve(ImageConfiguration.empty)
        .addListener(
          ImageStreamListener((ImageInfo info, bool _) {
            completer.complete(info.image);
          }),
        );
    return completer.future;
  }

  Future<Image> _applyAdjustAndConvert({
    required Image sourceImage,
    required double brightness,
    required double saturation,
    required bool invert,
  }) async {
    ui.Image adjustedImage = await _resolveUiImage(sourceImage);

    if (brightness != 0) {
      adjustedImage = await _createFilteredImage(adjustedImage, ColorFilter.matrix(brightnessAdjustMatrix(brightness)));
    }

    if (saturation != 0) {
      adjustedImage = await _createFilteredImage(adjustedImage, ColorFilter.matrix(saturationAdjustMatrix(saturation)));
    }

    if (invert) {
      adjustedImage = await _createFilteredImage(adjustedImage, const ColorFilter.matrix(invertColorMatrix));
    }

    final byteData = await adjustedImage.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    return Image.memory(pngBytes, fit: BoxFit.contain);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = useState<double>(0);
    final saturation = useState<double>(0);
    final invert = useState<bool>(false);
    final showOriginalPreview = useState<bool>(false);

    void resetAdjustments() {
      brightness.value = 0;
      saturation.value = 0;
      invert.value = false;
    }

    final hasChanges = brightness.value != 0 || saturation.value != 0 || invert.value;

    Widget adjustedPreview = image;
    adjustedPreview = BrightnessFilter(brightness: brightness.value, child: adjustedPreview);
    adjustedPreview = SaturationFilter(saturation: saturation.value, child: adjustedPreview);
    if (invert.value) {
      adjustedPreview = InvertionFilter(child: adjustedPreview);
    }

    return PlatformScaffold(
      appBar: PlatformAppBar(
        backgroundColor: context.scaffoldBackgroundColor,
        title: const Text("Adjust"),
        leading: CloseButton(color: context.primaryColor),
        trailingActions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: hasChanges ? context.primaryColor : Colors.grey, size: 22),
            onPressed: hasChanges ? resetAdjustments : null,
          ),
          IconButton(
            icon: Icon(Icons.done_rounded, color: context.primaryColor, size: 24),
            onPressed: () async {
              final adjustedImage = await _applyAdjustAndConvert(
                sourceImage: image,
                brightness: brightness.value,
                saturation: saturation.value,
                invert: invert.value,
              );
              unawaited(context.pushRoute(DriftEditImageRoute(asset: asset, image: adjustedImage, isEdited: true)));
            },
          ),
        ],
      ),
      backgroundColor: context.scaffoldBackgroundColor,
      body: Column(
        children: [
          SizedBox(
            height: context.height * 0.6,
            child: Center(
              child: GestureDetector(
                onLongPressStart: (_) => showOriginalPreview.value = true,
                onLongPressEnd: (_) => showOriginalPreview.value = false,
                onLongPressCancel: () => showOriginalPreview.value = false,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: showOriginalPreview.value
                          ? KeyedSubtree(key: const ValueKey('before_adjust_preview'), child: image)
                          : KeyedSubtree(key: const ValueKey('after_adjust_preview'), child: adjustedPreview),
                    ),
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: const BorderRadius.all(Radius.circular(999)),
                      ),
                      child: Text(
                        showOriginalPreview.value ? 'Before' : 'After',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                Text("Brightness (${brightness.value.toStringAsFixed(2)})", style: context.textTheme.bodyLarge),
                Slider(
                  value: brightness.value,
                  min: -1,
                  max: 1,
                  divisions: 200,
                  onChanged: (value) => brightness.value = value,
                ),
                Text("Saturation (${saturation.value.toStringAsFixed(2)})", style: context.textTheme.bodyLarge),
                Slider(
                  value: saturation.value,
                  min: -1,
                  max: 1,
                  divisions: 200,
                  onChanged: (value) => saturation.value = value,
                ),
                SwitchListTile.adaptive(
                  value: invert.value,
                  onChanged: (value) => invert.value = value,
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Invert Colors"),
                  subtitle: const Text("Toggle color inversion"),
                ),
                const SizedBox(height: 8),
                Text(
                  "Long press preview to compare",
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.textTheme.bodySmall?.color?.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
