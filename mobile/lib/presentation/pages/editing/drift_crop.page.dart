import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:crop_image/crop_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/hooks/crop_controller_hook.dart';

/// A widget for cropping an image.
/// This widget uses [HookWidget] to manage its lifecycle and state. It allows
/// users to crop an image and then navigate to the [EditImagePage] with the
/// cropped image.

@RoutePage()
class DriftCropImagePage extends HookWidget {
  final Image image;
  final BaseAsset asset;
  const DriftCropImagePage({super.key, required this.image, required this.asset});

  @override
  Widget build(BuildContext context) {
    final cropController = useCropController();
    final aspectRatio = useState<double?>(null);
    // pizcloud
    final ratioPresets = <MapEntry<String, double?>>[
      const MapEntry('Free', null),
      const MapEntry('1:1', 1.0),
      const MapEntry('16:9', 16.0 / 9.0),
      const MapEntry('3:2', 3.0 / 2.0),
      const MapEntry('7:5', 7.0 / 5.0),
      const MapEntry('4:5', 4.0 / 5.0),
      const MapEntry('9:16', 9.0 / 16.0),
      const MapEntry('2:3', 2.0 / 3.0),
      const MapEntry('5:4', 5.0 / 4.0),
    ];
    // #pizcloud

    return PlatformScaffold(
      appBar: PlatformAppBar(
        backgroundColor: context.scaffoldBackgroundColor,
        title: Text("crop".tr()),
        leading: CloseButton(color: context.primaryColor),
        trailingActions: [
          IconButton(
            icon: Icon(Icons.done_rounded, color: context.primaryColor, size: 24),
            onPressed: () async {
              final croppedImage = await cropController.croppedImage();
              unawaited(context.pushRoute(DriftEditImageRoute(asset: asset, image: croppedImage, isEdited: true)));
            },
          ),
        ],
      ),
      backgroundColor: context.scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.only(top: 20),
                  width: constraints.maxWidth * 0.9,
                  height: constraints.maxHeight * 0.6,
                  // pizcloud
                  // CropImage(controller: cropController, image: image, gridColor: Colors.white)
                  child: CropImage(
                    controller: cropController,
                    image: image,
                    gridColor: Colors.white,
                    alwaysShowThirdLines: true,
                    gridThinWidth: 1.5,
                    gridThickWidth: 3,
                    paddingSize: 8,
                    minimumImageSize: 80,
                    scrimColor: Colors.black.withValues(alpha: 0.55),
                  ),
                  // #pizcloud
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: context.scaffoldBackgroundColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.rotate_left, color: context.themeData.iconTheme.color),
                                  onPressed: () {
                                    cropController.rotateLeft();
                                  },
                                ),
                                IconButton(
                                  icon: Icon(Icons.rotate_right, color: context.themeData.iconTheme.color),
                                  onPressed: () {
                                    cropController.rotateRight();
                                  },
                                ),
                              ],
                            ),
                          ),
                          // pizcloud
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              children: ratioPresets
                                  .map(
                                    (preset) => Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 2),
                                      child: _AspectRatioButton(
                                        cropController: cropController,
                                        aspectRatio: aspectRatio,
                                        ratio: preset.value,
                                        label: preset.key,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                        // #pizcloud
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AspectRatioButton extends StatelessWidget {
  final CropController cropController;
  final ValueNotifier<double?> aspectRatio;
  final double? ratio;
  final String label;

  const _AspectRatioButton({
    required this.cropController,
    required this.aspectRatio,
    required this.ratio,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(switch (label) {
            'Free' => Icons.crop_free_rounded,
            '1:1' => Icons.crop_square_rounded,
            '16:9' => Icons.crop_16_9_rounded,
            '3:2' => Icons.crop_3_2_rounded,
            '7:5' => Icons.crop_7_5_rounded,
            // pizcloud
            '4:5' => Icons.crop_portrait_rounded,
            '9:16' => Icons.crop_portrait_rounded,
            '2:3' => Icons.crop_portrait_rounded,
            '5:4' => Icons.crop_5_4_rounded,
            // #pizcloud
            _ => Icons.crop_free_rounded,
          }, color: aspectRatio.value == ratio ? context.primaryColor : context.themeData.iconTheme.color),
          onPressed: () {
            cropController.crop = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
            aspectRatio.value = ratio;
            cropController.aspectRatio = ratio;
          },
        ),
        Text(label, style: context.textTheme.displayMedium),
      ],
    );
  }
}
