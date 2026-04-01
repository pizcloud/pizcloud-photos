import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/services/pizcloud/instruction_content.service.dart';

extension _InstructionFeatureView on InstructionFeature {
  String get titleKey => switch (this) {
    InstructionFeature.backup => 'backup',
    InstructionFeature.referral => 'referral_program',
    InstructionFeature.share => 'share',
    InstructionFeature.transferOwnership => 'transfer_ownership',
  };

  String get subtitleKey => switch (this) {
    InstructionFeature.backup => 'instructions_backup_subtitle',
    InstructionFeature.referral => 'instructions_referral_subtitle',
    InstructionFeature.share => 'instructions_share_subtitle',
    InstructionFeature.transferOwnership => 'instructions_transfer_ownership_subtitle',
  };

  IconData get materialIcon => switch (this) {
    InstructionFeature.backup => Icons.cloud_upload_outlined,
    InstructionFeature.referral => Icons.wallet_giftcard_outlined,
    InstructionFeature.share => Icons.share_outlined,
    InstructionFeature.transferOwnership => Icons.swap_horiz_rounded,
  };

  IconData get cupertinoIcon => switch (this) {
    InstructionFeature.backup => CupertinoIcons.cloud_upload,
    InstructionFeature.referral => CupertinoIcons.gift,
    InstructionFeature.share => CupertinoIcons.share,
    InstructionFeature.transferOwnership => CupertinoIcons.arrow_up_arrow_down,
  };
}

class InstructionsPage extends StatelessWidget {
  const InstructionsPage({super.key, this.contentService = const InstructionContentService()});

  final InstructionContentService contentService;

  static const _features = [
    InstructionFeature.backup,
    InstructionFeature.referral,
    InstructionFeature.share,
    InstructionFeature.transferOwnership,
  ];

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('instructions_title').tr(),
        material: (_, __) => MaterialAppBarData(centerTitle: false),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              'instructions_overview_subtitle'.tr(),
              style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            ..._features.map(
              (feature) => _InstructionFeatureCard(
                feature: feature,
                onTap: () => Navigator.of(context).push(
                  platformPageRoute(
                    context: context,
                    builder: (_) => InstructionSlidesPage(feature: feature, contentService: contentService),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstructionFeatureCard extends StatelessWidget {
  const _InstructionFeatureCard({required this.feature, required this.onTap});

  final InstructionFeature feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: context.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: context.colorScheme.outline.withValues(alpha: 0.16)),
        ),
        child: ListTile(
          minLeadingWidth: 42,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: const BorderRadius.all(Radius.circular(10)),
            ),
            child: Icon(
              context.platformIcon(material: feature.materialIcon, cupertino: feature.cupertinoIcon),
              size: 20,
              color: context.colorScheme.primary,
            ),
          ),
          title: Text(
            feature.titleKey.tr(),
            style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            feature.subtitleKey.tr(),
            style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
          trailing: Icon(context.platformIcons.rightChevron, size: 17, color: context.colorScheme.onSurfaceVariant),
          onTap: onTap,
        ),
      ),
    );
  }
}

class InstructionSlidesPage extends StatefulWidget {
  const InstructionSlidesPage({super.key, required this.feature, required this.contentService});

  final InstructionFeature feature;
  final InstructionContentService contentService;

  @override
  State<InstructionSlidesPage> createState() => _InstructionSlidesPageState();
}

class _InstructionSlidesPageState extends State<InstructionSlidesPage> {
  String _currentLanguageCode = 'en';
  late Future<List<InstructionSlide>> _slidesFuture = _loadSlides();
  final PageController _pageController = PageController();

  int _activePage = 0;

  Future<List<InstructionSlide>> _loadSlides() {
    return widget.contentService.fetchSlides(feature: widget.feature, languageCode: _currentLanguageCode);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = context.locale.languageCode;
    if (_currentLanguageCode == languageCode) {
      return;
    }

    _currentLanguageCode = languageCode;
    _activePage = 0;
    _slidesFuture = _loadSlides();
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  void _reload() {
    setState(() {
      _activePage = 0;
      _slidesFuture = _loadSlides();
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: Text(widget.feature.titleKey.tr()),
        material: (_, __) => MaterialAppBarData(centerTitle: false),
      ),
      body: SafeArea(
        child: FutureBuilder<List<InstructionSlide>>(
          future: _slidesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _InstructionsFeedbackState(
                messageKey: 'instructions_load_error',
                actionKey: 'retry',
                onAction: _reload,
              );
            }

            final slides = snapshot.data ?? const <InstructionSlide>[];
            if (slides.isEmpty) {
              return const _InstructionsFeedbackState(messageKey: 'instructions_empty_slides');
            }

            final currentPage = _activePage.clamp(0, slides.length - 1);
            final isLastPage = currentPage == slides.length - 1;

            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: context.colorScheme.surfaceContainerHighest,
                        borderRadius: const BorderRadius.all(Radius.circular(16)),
                        border: Border.all(color: context.colorScheme.outline.withValues(alpha: 0.2)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: slides.length,
                        onPageChanged: (value) => setState(() => _activePage = value),
                        itemBuilder: (context, index) {
                          final slide = slides[index];
                          return Column(
                            children: [
                              Expanded(
                                child: Center(
                                  child: Image.network(
                                    slide.imageUrl,
                                    fit: BoxFit.contain,
                                    loadingBuilder: (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return const Center(child: CircularProgressIndicator());
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return Center(
                                        child: Text(
                                          'instructions_load_error'.tr(),
                                          textAlign: TextAlign.center,
                                          style: context.textTheme.bodyMedium,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              if (slide.caption != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                                  child: Text(
                                    slide.caption!,
                                    textAlign: TextAlign.center,
                                    style: context.textTheme.bodySmall?.copyWith(
                                      color: context.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'instructions_slide_counter'.tr(
                      namedArgs: {'current': '${currentPage + 1}', 'total': '${slides.length}'},
                    ),
                    style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  _PageIndicator(count: slides.length, activeIndex: currentPage),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: currentPage == 0
                              ? null
                              : () => _pageController.previousPage(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut,
                                ),
                          child: const Text('back').tr(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            if (isLastPage) {
                              context.pop();
                              return;
                            }
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                            );
                          },
                          child: Text(isLastPage ? 'done'.tr() : 'next'.tr()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: List.generate(
        count,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: index == activeIndex ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(99)),
            color: index == activeIndex
                ? context.colorScheme.primary
                : context.colorScheme.outline.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

class _InstructionsFeedbackState extends StatelessWidget {
  const _InstructionsFeedbackState({required this.messageKey, this.actionKey, this.onAction});

  final String messageKey;
  final String? actionKey;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(messageKey.tr(), textAlign: TextAlign.center, style: context.textTheme.bodyMedium),
            if (actionKey != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(actionKey!.tr())),
            ],
          ],
        ),
      ),
    );
  }
}
