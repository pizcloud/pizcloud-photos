import 'dart:async';
import 'dart:ui' as ui;

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:immich_mobile/constants/filters.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/routing/router.dart';

/// A widget for filtering an image.
/// This widget uses [HookWidget] to manage its lifecycle and state. It allows
/// users to add filters to an image and then navigate to the [EditImagePage] with the
/// final composition.'
@RoutePage()
class DriftFilterImagePage extends HookWidget {
  final Image image;
  final BaseAsset asset;

  const DriftFilterImagePage({super.key, required this.image, required this.asset});

  @override
  Widget build(BuildContext context) {
    final colorFilter = useState<ColorFilter>(filters[0]);
    final selectedFilterIndex = useState<int>(0);
    final filterIntensity = useState<double>(1.0); // pizcloud
    final showOriginalPreview = useState<bool>(false); // pizcloud

    Future<ui.Image> createFilteredImage(ui.Image inputImage, ColorFilter filter) {
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

    // pizcloud
    Future<ui.Image> blendImages(ui.Image baseImage, ui.Image filteredImage, double opacity) {
      final completer = Completer<ui.Image>();
      final size = Size(baseImage.width.toDouble(), baseImage.height.toDouble());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      canvas.drawImage(baseImage, Offset.zero, Paint());
      canvas.drawImage(
        filteredImage,
        Offset.zero,
        Paint()..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0)),
      );

      recorder.endRecording().toImage(size.width.round(), size.height.round()).then((image) {
        completer.complete(image);
      });

      return completer.future;
    }
    // #pizcloud

    void applyFilter(ColorFilter filter, int index) {
      colorFilter.value = filter;
      selectedFilterIndex.value = index;
      // Previous behavior always applied selected preset fully (100%).
      filterIntensity.value = 1.0; // pizcloud
    }

    // pizcloud
    void resetFilter() {
      colorFilter.value = filters[0];
      selectedFilterIndex.value = 0;
      filterIntensity.value = 1.0;
    }
    // #pizcloud

    Future<Image> applyFilterAndConvert(ColorFilter filter, double intensity) async {
      final completer = Completer<ui.Image>();
      image.image
          .resolve(ImageConfiguration.empty)
          .addListener(
            ImageStreamListener((ImageInfo info, bool _) {
              completer.complete(info.image);
            }),
          );
      final uiImage = await completer.future;

      // pizcloud
      ui.Image outputImage = uiImage;
      final clampedIntensity = intensity.clamp(0.0, 1.0);

      if (clampedIntensity > 0) {
        final filteredUiImage = await createFilteredImage(uiImage, filter);
        outputImage = clampedIntensity >= 1
            ? filteredUiImage
            : await blendImages(uiImage, filteredUiImage, clampedIntensity);
      }
      // #pizcloud

      final byteData = await outputImage.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      return Image.memory(pngBytes, fit: BoxFit.contain);
    }

    return PlatformScaffold(
      appBar: PlatformAppBar(
        backgroundColor: context.scaffoldBackgroundColor,
        title: Text("filter".tr()),
        leading: CloseButton(color: context.primaryColor),
        trailingActions: [
          // pizcloud trailingActions only had the done/confirm action.
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: (selectedFilterIndex.value == 0 && filterIntensity.value == 1.0)
                  ? Colors.grey
                  : context.primaryColor,
              size: 22,
            ),
            onPressed: (selectedFilterIndex.value == 0 && filterIntensity.value == 1.0) ? null : resetFilter,
          ),
          // #pizcloud
          IconButton(
            icon: Icon(Icons.done_rounded, color: context.primaryColor, size: 24),
            onPressed: () async {
              final filteredImage = await applyFilterAndConvert(colorFilter.value, filterIntensity.value); // pizcloud
              unawaited(context.pushRoute(DriftEditImageRoute(asset: asset, image: filteredImage, isEdited: true)));
            },
          ),
        ],
      ),
      backgroundColor: context.scaffoldBackgroundColor,
      body: Column(
        children: [
          SizedBox(
            height: context.height * 0.64, // pizcloud
            child: Center(
              // pizcloud
              child: GestureDetector(
                onLongPressStart: (_) => showOriginalPreview.value = true,
                onLongPressEnd: (_) => showOriginalPreview.value = false,
                onLongPressCancel: () => showOriginalPreview.value = false,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Previous preview always rendered:
                    // ColorFiltered(colorFilter: colorFilter.value, child: image)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: showOriginalPreview.value
                          ? KeyedSubtree(key: const ValueKey('before_preview'), child: image)
                          : KeyedSubtree(
                              key: const ValueKey('after_preview'),
                              // pizcloud
                              child: Stack(
                                fit: StackFit.passthrough,
                                children: [
                                  image,
                                  if (filterIntensity.value > 0)
                                    Opacity(
                                      opacity: filterIntensity.value,
                                      child: ColorFiltered(colorFilter: colorFilter.value, child: image),
                                    ),
                                ],
                              ),
                              // #pizcloud
                            ),
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
              // #pizcloud
            ),
          ),
          // pizcloud
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const SizedBox(width: 58, child: Text("Intensity", maxLines: 1, overflow: TextOverflow.ellipsis)),
                Expanded(
                  child: Slider(
                    value: filterIntensity.value,
                    min: 0,
                    max: 1,
                    divisions: 100,
                    onChanged: (value) => filterIntensity.value = value,
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    "${(filterIntensity.value * 100).round()}%",
                    textAlign: TextAlign.right,
                    style: context.themeData.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          // #pizcloud
          SizedBox(
            height: 114, // pizcloud
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: filters.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: _FilterButton(
                    image: image,
                    label: filterNames[index],
                    filter: filters[index],
                    isSelected: selectedFilterIndex.value == index,
                    onTap: () => applyFilter(filters[index], index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final Image image;
  final String label;
  final ColorFilter filter;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterButton({
    required this.image,
    required this.label,
    required this.filter,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              border: isSelected ? Border.all(color: context.primaryColor, width: 3) : null,
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              child: ColorFiltered(
                colorFilter: filter,
                child: FittedBox(fit: BoxFit.cover, child: image),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: context.themeData.textTheme.bodyMedium),
      ],
    );
  }
}
