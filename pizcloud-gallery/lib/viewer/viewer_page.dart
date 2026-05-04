import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pizcloud_gallery/grid/media_hero_tag.dart';
import 'package:pizcloud_gallery/grid/media_item.dart';
import 'package:video_player/video_player.dart';

import 'physics/viewer_page_scroll_physics.dart';
import 'viewer_action.dart';
import 'viewer_action_menu.dart';
import 'viewer_appearance_config.dart';
import 'viewer_controller.dart';
import 'viewer_image_loader.dart';
import 'viewer_prefetcher.dart';
import 'viewer_route_names.dart'; // new
import 'viewer_session.dart';
import 'viewer_quick_actions_texts.dart'; // new
import 'widgets/viewer_zoomable.dart';

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key, required this.session});

  final ViewerSession session;

  static Future<void> open(
    BuildContext context, {
    required ViewerSession session,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        // new behavior did not set explicit route settings for the viewer route.
        settings: const RouteSettings(name: kPizGalleryViewerRouteName),
        opaque: false,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 360),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ViewerPage(session: session),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final Animation<double> opacity = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(opacity: opacity, child: child);
        },
      ),
    );
  }

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  static const double _viewerMinScale = 0.3;
  static const double _viewerMaxScale = 4.0;
  static const double _pageGapBase = 30.0;
  static const double _viewerTopBarTopPadding = 4.0;
  static const double _viewerTopBarHeight = 48.0;
  static const double _viewerBottomSafeMinimum = 4.0;
  static const double _viewerBottomActionBarHeight = 64.0;
  static const double _viewerMediaTopGap = 8.0;
  static const double _viewerMediaBottomGap = 8.0;
  static const double _viewerVideoControlsReserveHeight = 80.0;
  static const Duration _viewerViewportInsetAnimationDuration = Duration(
    milliseconds: 180,
  );
  static const bool _debugControlBarBorder = false;
  static bool _persistedVideoMuted = false;

  late final ViewerController _controller;
  late final List<ViewerAction> _actions;
  final ViewerPrefetcher _prefetcher = ViewerPrefetcher(maxItems: 10);
  final ValueNotifier<double> _currentViewerScale = ValueNotifier<double>(1.0);
  final ValueNotifier<double> _dismissDragProgress = ValueNotifier<double>(0.0);
  bool _isFullscreen = false;
  bool _isCurrentPageTransformed = false;
  bool _isCurrentPageGestureLocked = false;
  bool _isCurrentPageUnderlayReveal = false;
  bool _isDismissingFromZoom = false;
  bool _isSharingCurrentItem = false;
  bool _isDeletingCurrentItem = false;
  // new
  bool _isEditingCurrentItem = false;
  bool _isUploadingCurrentItem = false;
  bool _isAddingCurrentItem = false;
  // #new
  int _lastNotifiedVisibleIndex = -1;
  int _settledSideEffectToken = 0;
  final Map<String, VideoPlayerController> _videoControllersByItemId =
      <String, VideoPlayerController>{};
  VideoPlayerController? _activeSeekController;
  bool _isVideoSeekActive = false;
  bool _resumeVideoAfterSeek = false;
  bool _isVideoMuted = _persistedVideoMuted;

  @override
  void initState() {
    super.initState();
    _controller = ViewerController(session: widget.session)
      ..addListener(_handleStateChanged);
    // new
    final List<ViewerAction> customActions =
        widget.session.viewerActions ?? const <ViewerAction>[];
    // Old behavior: `_actions = DefaultViewerActions.build();`
    // Keep defaults unless host explicitly disables them.
    if (widget.session.includeDefaultViewerActions) {
      _actions = List<ViewerAction>.unmodifiable(<ViewerAction>[
        ...DefaultViewerActions.build(),
        ...customActions,
      ]);
    } else {
      _actions = List<ViewerAction>.unmodifiable(customActions);
    }
    // #new
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller.currentItem == null) return;
      _notifyVisibleIndexChanged(_controller.currentIndex);
      _prefetchAroundCurrentIndex();
    });
  }

  bool _canDeleteItem(MediaItem item) {
    final ViewerCanDeleteItemCallback? canDeleteItem =
        widget.session.canDeleteItem;
    if (canDeleteItem == null) {
      return true;
    }
    return canDeleteItem(item);
  }

  // new
  bool _canEditItem(MediaItem item) {
    final ViewerCanEditItemCallback? canEditItem = widget.session.canEditItem;
    if (canEditItem == null) {
      return true;
    }
    return canEditItem(item);
  }

  bool _canUploadItem(MediaItem item) {
    final ViewerCanUploadItemCallback? canUploadItem =
        widget.session.canUploadItem;
    if (canUploadItem == null) {
      return true;
    }
    return canUploadItem(item);
  }

  bool _canAddToAlbumItem(MediaItem item) {
    final ViewerCanAddToAlbumItemCallback? canAddToAlbumItem =
        widget.session.canAddToAlbumItem;
    if (canAddToAlbumItem == null) {
      return true;
    }
    return canAddToAlbumItem(item);
  }

  bool get _isAnyBottomActionInProgress =>
      _isSharingCurrentItem ||
      _isDeletingCurrentItem ||
      _isEditingCurrentItem ||
      _isUploadingCurrentItem ||
      _isAddingCurrentItem;
  // #new

  @override
  void dispose() {
    _restoreSystemUiMode();
    _dismissDragProgress.dispose();
    _currentViewerScale.dispose();
    _controller.removeListener(_handleStateChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleVideoControllerChanged(
    String itemId,
    VideoPlayerController? controller,
  ) {
    final MediaItem? current = _controller.currentItem;
    final bool affectsCurrent = current?.id == itemId;
    if (controller == null) {
      final VideoPlayerController? removed = _videoControllersByItemId.remove(
        itemId,
      );
      if (identical(removed, _activeSeekController)) {
        _activeSeekController = null;
        _isVideoSeekActive = false;
        _resumeVideoAfterSeek = false;
      }
      if (removed != null && affectsCurrent && mounted) {
        setState(() {});
      }
      return;
    }
    final VideoPlayerController? previous = _videoControllersByItemId[itemId];
    if (identical(previous, controller)) {
      return;
    }
    _videoControllersByItemId[itemId] = controller;
    _applyMutedStateToController(controller);
    if (affectsCurrent && mounted) {
      setState(() {});
    }
  }

  void _setControllerVolume(VideoPlayerController controller, double volume) {
    try {
      unawaited(controller.setVolume(volume));
    } catch (_) {
      // Ignore transient errors while controller is being replaced/disposed.
    }
  }

  void _applyMutedStateToController(VideoPlayerController controller) {
    final double targetVolume = _isVideoMuted ? 0.0 : 1.0;
    final double currentVolume = controller.value.volume;
    if ((currentVolume - targetVolume).abs() < 0.001) {
      return;
    }
    _setControllerVolume(controller, targetVolume);
  }

  void _setVideoMuted(bool muted) {
    if (_isVideoMuted == muted) {
      return;
    }
    _persistedVideoMuted = muted;
    if (mounted) {
      setState(() {
        _isVideoMuted = muted;
      });
    } else {
      _isVideoMuted = muted;
    }
    final double targetVolume = muted ? 0.0 : 1.0;
    for (final VideoPlayerController controller
        in _videoControllersByItemId.values) {
      _setControllerVolume(controller, targetVolume);
    }
  }

  void _beginVideoSeek(VideoPlayerController controller) {
    if (_isVideoSeekActive && identical(_activeSeekController, controller)) {
      return;
    }
    _activeSeekController = controller;
    _isVideoSeekActive = true;
    _resumeVideoAfterSeek = controller.value.isPlaying;
    if (_resumeVideoAfterSeek) {
      unawaited(controller.pause());
    }
  }

  void _endVideoSeek(VideoPlayerController controller) {
    if (!_isVideoSeekActive || !identical(_activeSeekController, controller)) {
      return;
    }
    final bool shouldResume = _resumeVideoAfterSeek;
    _activeSeekController = null;
    _isVideoSeekActive = false;
    _resumeVideoAfterSeek = false;
    if (shouldResume) {
      unawaited(controller.play());
    }
  }

  void _toggleFullscreen() {
    if (!mounted || _isDismissingFromZoom) return;
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    _applySystemUiModeForViewer();
  }

  void _applySystemUiModeForViewer() {
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        _isFullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
  }

  void _restoreSystemUiMode() {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }

  void _handlePageChanged(int _) {
    // Intentionally do nothing here.
    // We commit page state only on scroll end to avoid mid-swipe jank.
  }

  bool _handlePageScrollNotification(ScrollNotification notification) {
    // Avoid heavy grid-sync while dragging around the 0.5 page threshold.
    // Sync only when the horizontal page motion settles.
    if (notification.metrics.axis != Axis.horizontal) return false;
    if (notification is! ScrollEndNotification) return false;
    final int settledIndex = _resolveVisibleIndex();
    if (settledIndex != _controller.currentIndex) {
      _commitSettledPageChange(settledIndex);
    }
    _scheduleSettledSideEffects(settledIndex);
    return false;
  }

  void _scheduleSettledSideEffects(int settledIndex) {
    final int token = ++_settledSideEffectToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _settledSideEffectToken) return;
      _notifyVisibleIndexChanged(settledIndex);
      _prefetchAroundCurrentIndex();
    });
  }

  void _commitSettledPageChange(int nextIndex) {
    if (nextIndex < 0 || nextIndex >= _controller.totalCount) return;
    if (_dismissDragProgress.value != 0.0) {
      _dismissDragProgress.value = 0.0;
    }
    if (_isDismissingFromZoom) {
      _isDismissingFromZoom = false;
    }
    if (_isCurrentPageTransformed) {
      _isCurrentPageTransformed = false;
    }
    if (_isCurrentPageGestureLocked) {
      _isCurrentPageGestureLocked = false;
    }
    if (_isCurrentPageUnderlayReveal) {
      _isCurrentPageUnderlayReveal = false;
    }
    if (_currentViewerScale.value != 1.0) {
      _currentViewerScale.value = 1.0;
    }
    _controller.onPageChanged(nextIndex);
  }

  void _prefetchAroundCurrentIndex() {
    if (!mounted || _controller.currentItem == null) return;
    _prefetcher.prefetchAround(
      context: context,
      items: _controller.items,
      centerIndex: _controller.currentIndex,
    );
  }

  bool _isEventForVisiblePage(int pageIndex) {
    if (pageIndex == _controller.currentIndex) return true;
    return pageIndex == _resolveVisibleIndex();
  }

  int _resolveVisibleIndex() {
    final int total = _controller.totalCount;
    if (total <= 0) return 0;
    final PageController pageController = _controller.pageController;
    if (!pageController.hasClients) {
      return _controller.currentIndex.clamp(0, total - 1);
    }
    final double? page = pageController.page;
    if (page == null || !page.isFinite) {
      return _controller.currentIndex.clamp(0, total - 1);
    }
    return page.round().clamp(0, total - 1);
  }

  void _notifyVisibleIndexChanged(int index) {
    final int total = _controller.totalCount;
    if (total <= 0) return;
    final int clamped = index.clamp(0, total - 1);
    if (clamped == _lastNotifiedVisibleIndex) return;
    _lastNotifiedVisibleIndex = clamped;
    widget.session.onVisibleIndexChanged?.call(clamped);
  }

  void _handleTransformStateChanged(int pageIndex, bool isTransformed) {
    if (!_isEventForVisiblePage(pageIndex)) return;
    if (_isCurrentPageTransformed == isTransformed) return;
    setState(() {
      _isCurrentPageTransformed = isTransformed;
    });
  }

  void _handleGestureLockChanged(int pageIndex, bool isLocked) {
    if (!_isEventForVisiblePage(pageIndex)) return;
    if (_isCurrentPageGestureLocked == isLocked) return;
    setState(() {
      _isCurrentPageGestureLocked = isLocked;
    });
  }

  void _handleUnderlayRevealChanged(int pageIndex, bool reveal) {
    if (_isDismissingFromZoom) return;
    if (!_isEventForVisiblePage(pageIndex)) return;
    final bool shouldExitFullscreen = reveal && _isFullscreen;
    if (_isCurrentPageUnderlayReveal == reveal && !shouldExitFullscreen) return;
    setState(() {
      _isCurrentPageUnderlayReveal = reveal;
      if (shouldExitFullscreen) {
        _isFullscreen = false;
      }
    });
    if (shouldExitFullscreen) {
      _applySystemUiModeForViewer();
    }
  }

  void _handleScaleChanged(int pageIndex, double scale) {
    if (_isDismissingFromZoom) return;
    if (!_isEventForVisiblePage(pageIndex)) return;
    final double clamped = scale.clamp(_viewerMinScale, _viewerMaxScale);
    if ((_currentViewerScale.value - clamped).abs() < 0.001) {
      return;
    }
    _currentViewerScale.value = clamped;
  }

  void _handleDismissDragProgressChanged(int pageIndex, double progress) {
    _updateDismissGestureProgress(pageIndex, progress);
  }

  void _handleDismissScaleProgressChanged(int pageIndex, double progress) {
    _updateDismissGestureProgress(pageIndex, progress);
  }

  String _formatDuration(Duration duration) {
    if (duration <= Duration.zero) {
      return '00:00';
    }
    final int totalSeconds = duration.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // new
  List<BoxShadow> _overlayChipShadows(
    ViewerAppearancePalette palette, {
    bool strong = false,
  }) {
    return <BoxShadow>[
      BoxShadow(
        color: strong
            ? palette.overlayChipStrongShadow
            : palette.overlayChipShadow,
        blurRadius: strong ? 18 : 14,
        offset: strong ? const Offset(0, 8) : const Offset(0, 5),
      ),
    ];
  }

  Color _overlayButtonBackgroundColor(ViewerAppearancePalette palette) {
    // Viewer background is now black in both light/dark appearance modes.
    // Use a stronger iOS-like translucent gray so chip backgrounds are always visible.
    return const Color(0xE62C2C2E);
  }

  Widget _buildOverlayIconChipButton({
    required ViewerAppearancePalette palette,
    required IconData icon,
    required VoidCallback? onPressed,
    Color? iconColor,
    double iconSize = 22,
    double buttonSize = 40,
    bool strongShadow = false,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _overlayButtonBackgroundColor(palette),
        shape: BoxShape.circle,
        border: Border.all(
          color: palette.overlayChipBorder.withValues(alpha: 0.55),
        ),
        boxShadow: _overlayChipShadows(palette, strong: strongShadow),
      ),
      child: SizedBox(
        width: buttonSize,
        height: buttonSize,
        child: IconButton(
          padding: EdgeInsets.zero,
          splashRadius: buttonSize / 2,
          onPressed: onPressed,
          icon: Icon(
            icon,
            color: iconColor ?? palette.overlayControlForeground,
            size: iconSize,
          ),
        ),
      ),
    );
  }
  // #new

  Widget _buildExternalVideoControls(
    ViewerAppearancePalette palette,
    VideoPlayerController controller,
  ) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final VideoPlayerValue value = controller.value;
        if (!value.isInitialized || value.hasError) {
          return const SizedBox.shrink();
        }
        final Duration duration = value.duration;
        final Duration position = value.position > duration
            ? duration
            : value.position;
        final int durationSeconds = duration.inSeconds;
        final double maxSeconds = durationSeconds <= 0
            ? 1.0
            : durationSeconds.toDouble();
        final double currentSeconds = position.inSeconds.toDouble().clamp(
          0.0,
          maxSeconds,
        );
        final bool canSeek = durationSeconds > 0;
        final bool isPlaying = value.isPlaying;
        final bool isMuted = _isVideoMuted;
        // new
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Container(
            decoration: _debugControlBarBorder
                ? BoxDecoration(
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0),
                      width: 0.0,
                    ),
                  )
                : BoxDecoration(
                    // color: palette.videoControlsPanelBackground,
                    borderRadius: BorderRadius.circular(22),
                    // border: Border.all(color: palette.overlayChipBorder),
                    boxShadow: _overlayChipShadows(palette, strong: true),
                  ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _buildOverlayIconChipButton(
                        palette: palette,
                        icon: isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        iconSize: 24,
                        buttonSize: 36,
                        onPressed: () {
                          if (isPlaying) {
                            unawaited(controller.pause());
                          } else {
                            unawaited(controller.play());
                          }
                        },
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '${_formatDuration(position)} / ${_formatDuration(duration)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: palette.overlayControlForeground,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              shadows: <Shadow>[
                                Shadow(
                                  color: palette.overlayChipStrongShadow,
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _buildOverlayIconChipButton(
                        palette: palette,
                        icon: isMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        onPressed: () {
                          _setVideoMuted(!isMuted);
                        },
                        buttonSize: 36,
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      overlayShape: SliderComponentShape.noOverlay,
                      trackHeight: 4,
                      thumbShape: const _VerticalBarSliderThumbShape(
                        width: 5,
                        height: 32,
                        radius: 1.5,
                      ),
                    ),
                    child: Padding(
                      // Old behavior used larger symmetric padding; keep tighter spacing for floating panel.
                      padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
                      child: Slider(
                        padding: EdgeInsets.zero,
                        min: 0,
                        max: maxSeconds,
                        value: currentSeconds,
                        activeColor: palette.overlayControlForeground,
                        inactiveColor: palette.overlayControlDisabledForeground,
                        onChangeStart: canSeek
                            ? (_) {
                                _beginVideoSeek(controller);
                              }
                            : null,
                        onChanged: canSeek
                            ? (value) {
                                unawaited(
                                  controller.seekTo(
                                    Duration(seconds: value.toInt()),
                                  ),
                                );
                              }
                            : null,
                        onChangeEnd: canSeek
                            ? (_) {
                                _endVideoSeek(controller);
                              }
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      // #new
    );
  }

  void _updateDismissGestureProgress(int pageIndex, double progress) {
    if (_isDismissingFromZoom) return;
    if (!_isEventForVisiblePage(pageIndex)) return;
    final double clamped = progress.clamp(0.0, 1.0);
    if ((_dismissDragProgress.value - clamped).abs() < 0.005) return;
    _dismissDragProgress.value = clamped;
    if (clamped > 0.0 && _isFullscreen) {
      setState(() {
        _isFullscreen = false;
      });
      _applySystemUiModeForViewer();
    }
  }

  double _resolvePageGap() {
    return _pageGapBase;
  }

  double _resolvePageTranslationX({
    required int pageIndex,
    required double currentPage,
    required double gap,
  }) {
    final double delta = pageIndex - currentPage;
    if (delta == 0) return 0;
    final double distance = delta.abs().clamp(0.0, 1.0);
    final double eased = Curves.easeOut.transform(distance);
    return delta.sign * gap * eased;
  }

  Future<void> _dismissViewerFromZoom() async {
    if (!mounted || _isDismissingFromZoom) return;
    _restoreSystemUiMode();
    setState(() {
      _isDismissingFromZoom = true;
    });
    // Ensure transparent underlay is rendered before Hero pop captures source.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final bool popped = await Navigator.of(context).maybePop();
    if (!popped && mounted) {
      setState(() {
        _isDismissingFromZoom = false;
      });
    }
  }

  Future<void> _onActionSelected(ViewerAction action) async {
    final MediaItem? item = _controller.currentItem;
    if (item == null) return;
    await action.execute(
      ViewerActionContext(context: context, controller: _controller),
      item,
    );
  }

  Future<void> _onSharePressed() async {
    final MediaItem? item = _controller.currentItem;
    if (item == null || _isAnyBottomActionInProgress) {
      // new
      return;
    }
    setState(() {
      _isSharingCurrentItem = true;
    });
    try {
      final ViewerShareCallback? onShareRequested =
          widget.session.onShareRequested;
      if (onShareRequested != null) {
        await onShareRequested(item);
      } else {
        await Clipboard.setData(ClipboardData(text: item.originalUrl));
        if (!mounted) return;
        final String message = item.isLocal
            ? 'Media reference copied'
            : 'Media URL copied';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Share failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isSharingCurrentItem = false;
        });
      }
    }
  }

  Future<bool> _confirmDeleteCurrentItem(MediaItem item) async {
    final String mediaLabel = item.isVideo ? 'Video' : 'Photo';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Delete this ${mediaLabel.toLowerCase()}?'),
          content: Text(
            '$mediaLabel will be deleted from Library and moved to Recently Deleted for 30 days.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _onDeletePressed() async {
    final MediaItem? item = _controller.currentItem;
    final ViewerDeleteCallback? onDeleteRequested =
        widget.session.onDeleteRequested;
    // new
    if (item == null ||
        onDeleteRequested == null ||
        _isAnyBottomActionInProgress ||
        !_canDeleteItem(item)) {
      return;
    }
    // #new
    final bool confirmed = await _confirmDeleteCurrentItem(item);
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _isDeletingCurrentItem = true;
    });
    try {
      await onDeleteRequested(item);
      if (!mounted) return;
      final ViewerDeleteResult? result = _controller.removeCurrentItem();
      if (result == null) {
        return;
      }
      if (result.isEmpty) {
        await _dismissViewerFromZoom();
        return;
      }
      if (_dismissDragProgress.value != 0.0) {
        _dismissDragProgress.value = 0.0;
      }
      if (_currentViewerScale.value != 1.0) {
        _currentViewerScale.value = 1.0;
      }
      _lastNotifiedVisibleIndex = -1;
      _notifyVisibleIndexChanged(result.currentIndex);
      _prefetchAroundCurrentIndex();
      if (mounted) {
        setState(() {
          _isCurrentPageTransformed = false;
          _isCurrentPageGestureLocked = false;
          _isCurrentPageUnderlayReveal = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      // new
      final String errorMessage = _extractDeleteErrorMessage(error);

      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(content: Text('Delete failed: $error')),
      // );
      await _showViewerActionErrorDialog(
        title: 'Delete failed',
        message: errorMessage,
      );
      // #new
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingCurrentItem = false;
        });
      }
    }
  }

  // new
  String _extractDeleteErrorMessage(Object error) {
    final String raw = error.toString().trim();
    if (raw.isEmpty) {
      return 'Delete failed';
    }

    const prefixes = <String>['Exception: ', 'Bad state: ', 'StateError: '];
    for (final prefix in prefixes) {
      if (raw.startsWith(prefix)) {
        final normalized = raw.substring(prefix.length).trim();
        if (normalized.isNotEmpty) {
          return normalized;
        }
      }
    }

    return raw;
  }

  Future<void> _showViewerActionErrorDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    final normalizedMessage = message.trim().isEmpty ? title : message;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(normalizedMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                MaterialLocalizations.of(dialogContext).okButtonLabel,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onEditPressed() async {
    final MediaItem? item = _controller.currentItem;
    final ViewerEditCallback? onEditRequested = widget.session.onEditRequested;
    if (item == null ||
        onEditRequested == null ||
        _isAnyBottomActionInProgress ||
        !_canEditItem(item)) {
      return;
    }
    setState(() {
      _isEditingCurrentItem = true;
    });
    try {
      await onEditRequested(item);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Edit failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isEditingCurrentItem = false;
        });
      }
    }
  }

  Future<void> _onUploadPressed() async {
    final MediaItem? item = _controller.currentItem;
    final ViewerUploadCallback? onUploadRequested =
        widget.session.onUploadRequested;
    if (item == null ||
        onUploadRequested == null ||
        _isAnyBottomActionInProgress ||
        !_canUploadItem(item)) {
      return;
    }
    setState(() {
      _isUploadingCurrentItem = true;
    });
    try {
      await onUploadRequested(item);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingCurrentItem = false;
        });
      }
    }
  }

  Future<void> _onAddToAlbumPressed() async {
    final MediaItem? item = _controller.currentItem;
    final ViewerAddToAlbumCallback? onAddToAlbumRequested =
        widget.session.onAddToAlbumRequested;
    if (item == null ||
        onAddToAlbumRequested == null ||
        _isAnyBottomActionInProgress ||
        !_canAddToAlbumItem(item)) {
      return;
    }
    setState(() {
      _isAddingCurrentItem = true;
    });
    try {
      await onAddToAlbumRequested(item);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Add to album failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isAddingCurrentItem = false;
        });
      }
    }
  }

  Future<void> _showQuickActionsSheet({
    required bool canUploadCurrentItem,
    required bool canEditCurrentItem,
    required bool canAddToAlbumCurrentItem,
    required bool canDeleteCurrentItem,
  }) async {
    if (!mounted || _isAnyBottomActionInProgress) {
      return;
    }
    final ViewerQuickActionsTexts texts = widget.session.quickActionsTexts;
    final String? rawMessage = texts.quickActionsSheetMessage?.trim();
    final String? sheetMessage = rawMessage == null || rawMessage.isEmpty
        ? null
        : rawMessage;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) {
        return CupertinoActionSheet(
          title: Text(texts.quickActionsSheetTitle),
          message: sheetMessage == null ? null : Text(sheetMessage),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                unawaited(_onSharePressed());
              },
              child: Text(texts.shareLabel),
            ),
            if (canUploadCurrentItem)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_onUploadPressed());
                },
                child: Text(texts.uploadLabel),
              ),
            if (canEditCurrentItem)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_onEditPressed());
                },
                child: Text(texts.editLabel),
              ),
            if (canAddToAlbumCurrentItem)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_onAddToAlbumPressed());
                },
                child: Text(texts.addToAlbumLabel),
              ),
            if (canDeleteCurrentItem)
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_onDeletePressed());
                },
                child: Text(texts.deleteLabel),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: Text(texts.cancelLabel),
          ),
        );
      },
    );
  }

  // new
  Widget _buildTopOverlayIconButton({
    required ViewerAppearancePalette palette,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return _buildOverlayIconChipButton(
      palette: palette,
      icon: icon,
      onPressed: onPressed,
      strongShadow: true,
    );
  }
  // #new

  Widget _buildBottomActionButton({
    required ViewerAppearancePalette palette,
    required IconData icon,
    required String label,
    required bool isBusy,
    required String busyLabel,
    required VoidCallback? onPressed,
  }) {
    // new behavior used `palette.appBarForeground` directly for icon/text colors.
    final Color actionColor = onPressed == null
        ? palette.overlayControlDisabledForeground
        : palette.overlayControlForeground;
    return Expanded(
      child: Align(
        alignment: Alignment.center,
        child: _buildOverlayIconChipButton(
          palette: palette,
          icon: icon,
          iconColor: actionColor,
          onPressed: onPressed,
          iconSize: 28,
          buttonSize: 52,
          strongShadow: true,
        ),
      ),
    );
  }
  // #new

  EdgeInsets _resolveViewerMediaViewportInsets({
    required MediaQueryData mediaQuery,
    required bool showTopBar,
    required bool showBottomBar,
    required bool reserveVideoControlsSpace,
  }) {
    // Old behavior rendered media edge-to-edge behind bars.
    // Reserve a center viewport so very tall photos don't visually collide with top/bottom controls.
    if (!showTopBar && !showBottomBar) {
      return EdgeInsets.zero;
    }

    double topInset = 0;
    if (showTopBar) {
      topInset =
          mediaQuery.padding.top +
          _viewerTopBarTopPadding +
          _viewerTopBarHeight +
          _viewerMediaTopGap;
    }

    double bottomInset = 0;
    if (showBottomBar) {
      bottomInset =
          mediaQuery.padding.bottom +
          _viewerBottomSafeMinimum +
          _viewerBottomActionBarHeight +
          _viewerMediaBottomGap;
      if (reserveVideoControlsSpace) {
        bottomInset += _viewerVideoControlsReserveHeight;
      }
    }

    return EdgeInsets.only(top: topInset, bottom: bottomInset);
  }

  @override
  Widget build(BuildContext context) {
    final ViewerAppearancePalette palette = ViewerAppearancePalette.of(context);
    if (_controller.items.isEmpty) {
      return Scaffold(
        backgroundColor: palette.scaffoldBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: palette.appBarForeground,
        ),
        body: Center(
          child: Text(
            'No media to display',
            style: TextStyle(color: palette.emptyStateText),
          ),
        ),
      );
    }

    final MediaItem item = _controller.currentItem!;
    final bool canDeleteCurrentItem =
        widget.session.onDeleteRequested != null && _canDeleteItem(item); // new
    // new
    final bool canEditCurrentItem =
        widget.session.onEditRequested != null && _canEditItem(item);
    final bool canUploadCurrentItem =
        widget.session.onUploadRequested != null && _canUploadItem(item);
    final bool canAddToAlbumCurrentItem =
        widget.session.onAddToAlbumRequested != null &&
        _canAddToAlbumItem(item);
    final ViewerQuickActionsTexts quickActionsTexts =
        widget.session.quickActionsTexts;
    // #new
    final VideoPlayerController? currentVideoController = item.isVideo
        ? _videoControllersByItemId[item.id]
        : null;
    final int humanIndex = _controller.currentIndex + 1;
    final String title = '$humanIndex / ${_controller.totalCount}';

    return ValueListenableBuilder<double>(
      valueListenable: _currentViewerScale,
      builder: (context, _, child) {
        final double pageGap = _resolvePageGap();
        final bool revealUnderlay =
            _isDismissingFromZoom || _isCurrentPageUnderlayReveal;
        final bool showTopBar = !revealUnderlay && !_isFullscreen;
        final bool showBottomBar = !revealUnderlay && !_isFullscreen;
        // Old behavior used palette-dependent background in non-fullscreen mode.
        final Color backdropBaseColor = Colors.black;
        return ValueListenableBuilder<double>(
          valueListenable: _dismissDragProgress,
          builder: (context, dismissDragProgress, _) {
            final double backdropOpacity = _isDismissingFromZoom
                ? 0.0
                : (dismissDragProgress > 0
                      ? (1.0 - dismissDragProgress).clamp(0.0, 1.0)
                      : (revealUnderlay ? 0.0 : 1.0));
            final MediaQueryData mediaQuery = MediaQuery.of(context);
            final MediaQueryData viewerMediaQuery = _isFullscreen
                ? mediaQuery.copyWith(
                    padding: EdgeInsets.zero,
                    viewPadding: EdgeInsets.zero,
                    viewInsets: EdgeInsets.zero,
                  )
                : mediaQuery;
            final EdgeInsets viewerMediaViewportInsets =
                _resolveViewerMediaViewportInsets(
                  mediaQuery: viewerMediaQuery,
                  showTopBar: showTopBar,
                  showBottomBar: showBottomBar,
                  reserveVideoControlsSpace:
                      showBottomBar && currentVideoController != null,
                );
            return PopScope<void>(
              canPop: _isDismissingFromZoom,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop || _isDismissingFromZoom) return;
                unawaited(_dismissViewerFromZoom());
              },
              child: MediaQuery(
                data: viewerMediaQuery,
                child: Material(
                  color: revealUnderlay ? Colors.transparent : Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: backdropBaseColor.withValues(
                          alpha: backdropOpacity,
                        ),
                      ),
                      AnimatedPadding(
                        duration: _viewerViewportInsetAnimationDuration,
                        curve: Curves.easeOutCubic,
                        padding: viewerMediaViewportInsets,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _handlePageScrollNotification,
                          child: PageView.builder(
                            controller: _controller.pageController,
                            physics: _isCurrentPageGestureLocked
                                ? const NeverScrollableScrollPhysics()
                                : const ViewerPageScrollPhysics(),
                            itemCount: _controller.totalCount,
                            onPageChanged: _handlePageChanged,
                            itemBuilder: (context, index) {
                              final MediaItem pageItem =
                                  _controller.items[index];
                              final bool startWithHighQuality =
                                  index == widget.session.clampedInitialIndex &&
                                  widget.session.initialOriginalReady;
                              final String? initialThumbUrl =
                                  index == widget.session.clampedInitialIndex
                                  ? widget.session.initialThumbUrl
                                  : null; // new
                              final initialThumbBytes =
                                  index == widget.session.clampedInitialIndex
                                  ? widget.session.initialThumbBytes
                                  : null; // new
                              final bool isCurrentPage =
                                  index == _controller.currentIndex;
                              final String heroTag = mediaViewerHeroTag(
                                pageItem.id,
                              );
                              final double mediaAspectRatio =
                                  _resolveMediaAspectRatio(pageItem);
                              final Widget imageChild = ViewerImageLoader(
                                item: pageItem,
                                viewerIndex: index,
                                isActive: isCurrentPage,
                                onSurfaceTap: _toggleFullscreen,
                                startWithHighQuality: startWithHighQuality,
                                initialThumbUrl: initialThumbUrl, // new
                                initialThumbBytes: initialThumbBytes, // new
                                useTransparentBackground:
                                    isCurrentPage && revealUnderlay,
                                useBlackBackground: _isFullscreen,
                                videoControlsBottomInset: 12,
                                videoControlsEnabled: false,
                                onVideoControllerChanged: (controller) {
                                  _handleVideoControllerChanged(
                                    pageItem.id,
                                    controller,
                                  );
                                },
                              );
                              return SafeArea(
                                top: false,
                                bottom: false,
                                child: AnimatedBuilder(
                                  animation: _controller.pageController,
                                  child: ViewerZoomable(
                                    key: ValueKey<String>(
                                      'viewer_zoom_${pageItem.id}',
                                    ),
                                    heroTag: heroTag,
                                    mediaAspectRatio: mediaAspectRatio,
                                    enabled: true,
                                    minScale: _viewerMinScale,
                                    maxScale: _viewerMaxScale,
                                    onTransformStateChanged: (isTransformed) {
                                      _handleTransformStateChanged(
                                        index,
                                        isTransformed,
                                      );
                                    },
                                    onGestureLockChanged: (isLocked) {
                                      _handleGestureLockChanged(
                                        index,
                                        isLocked,
                                      );
                                    },
                                    onUnderlayRevealChanged: (reveal) {
                                      _handleUnderlayRevealChanged(
                                        index,
                                        reveal,
                                      );
                                    },
                                    onScaleChanged: (currentScale) {
                                      _handleScaleChanged(index, currentScale);
                                    },
                                    onDismissDragProgressChanged: (progress) {
                                      _handleDismissDragProgressChanged(
                                        index,
                                        progress,
                                      );
                                    },
                                    onDismissScaleProgressChanged: (progress) {
                                      _handleDismissScaleProgressChanged(
                                        index,
                                        progress,
                                      );
                                    },
                                    onSingleTap: _toggleFullscreen,
                                    onDismissRequested: _dismissViewerFromZoom,
                                    child: imageChild,
                                  ),
                                  builder: (context, child) {
                                    double currentPage = _controller
                                        .currentIndex
                                        .toDouble();
                                    final PageController pageController =
                                        _controller.pageController;
                                    if (pageController.hasClients) {
                                      final double? livePage =
                                          pageController.page;
                                      if (livePage != null &&
                                          livePage.isFinite) {
                                        currentPage = livePage;
                                      }
                                    }
                                    final double dx = _resolvePageTranslationX(
                                      pageIndex: index,
                                      currentPage: currentPage,
                                      gap: pageGap,
                                    );
                                    return Transform.translate(
                                      offset: Offset(dx, 0),
                                      child: child,
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      if (showTopBar)
                        Align(
                          alignment: Alignment.topCenter,
                          // new
                          child: SafeArea(
                            bottom: false,
                            child: Padding(
                              // Old behavior used a full-width gradient scrim as top bar background.
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                _viewerTopBarTopPadding,
                                12,
                                0,
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                height: _viewerTopBarHeight,
                                child: NavigationToolbar(
                                  leading: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _buildTopOverlayIconButton(
                                      palette: palette,
                                      icon: Icons.arrow_back,
                                      onPressed: _dismissViewerFromZoom,
                                    ),
                                  ),
                                  middle: Text(
                                    title,
                                    style: TextStyle(
                                      color: palette.overlayControlForeground,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      shadows: <Shadow>[
                                        Shadow(
                                          color:
                                              palette.overlayChipStrongShadow,
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                  ),
                                  trailing: Align(
                                    alignment: Alignment.centerRight,
                                    child: ViewerActionMenu(
                                      actions: _actions,
                                      item: item,
                                      onSelected: _onActionSelected,
                                      iconColor:
                                          palette.overlayControlForeground,
                                      iconBackgroundColor:
                                          _overlayButtonBackgroundColor(
                                            palette,
                                          ),
                                      iconBorderColor: palette.overlayChipBorder
                                          .withValues(alpha: 0.30),
                                      iconShadowColor:
                                          palette.overlayChipStrongShadow,
                                    ),
                                  ),
                                  centerMiddle: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // #new
                      if (showBottomBar)
                        Align(
                          // new
                          alignment: Alignment.bottomCenter,
                          child: SafeArea(
                            top: false,
                            minimum: EdgeInsets.fromLTRB(
                              8,
                              0,
                              8,
                              _viewerBottomSafeMinimum,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (currentVideoController != null)
                                  _buildExternalVideoControls(
                                    palette,
                                    currentVideoController,
                                  ),
                                GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onHorizontalDragStart: (_) {},
                                  onHorizontalDragUpdate: (_) {},
                                  onHorizontalDragEnd: (_) {},
                                  child: SizedBox(
                                    height: _viewerBottomActionBarHeight,
                                    // width: 150,
                                    child: Padding(
                                      // Old behavior used a full-width bottom scrim panel.
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        // Old behavior rendered multiple fixed buttons directly in the bar.
                                        // Keep previous implementation as reference for quick rollback/debug.
                                        // children: [
                                        //   _buildBottomActionButton(
                                        //     palette: palette,
                                        //     icon: Icons.share_outlined,
                                        //     label: 'Share',
                                        //     isBusy: _isSharingCurrentItem,
                                        //     busyLabel: 'Sharing...',
                                        //     onPressed:
                                        //         _isAnyBottomActionInProgress
                                        //         ? null
                                        //         : _onSharePressed,
                                        //   ),
                                        //   if (canUploadCurrentItem)
                                        //     _buildBottomActionButton(
                                        //       palette: palette,
                                        //       icon: Icons.backup_outlined,
                                        //       label: 'Upload',
                                        //       isBusy: _isUploadingCurrentItem,
                                        //       busyLabel: 'Uploading...',
                                        //       onPressed:
                                        //           _isAnyBottomActionInProgress
                                        //           ? null
                                        //           : _onUploadPressed,
                                        //     ),
                                        //   if (canEditCurrentItem)
                                        //     _buildBottomActionButton(
                                        //       palette: palette,
                                        //       icon: Icons.edit_square,
                                        //       label: 'Edit',
                                        //       isBusy: _isEditingCurrentItem,
                                        //       busyLabel: 'Opening...',
                                        //       onPressed:
                                        //           _isAnyBottomActionInProgress
                                        //           ? null
                                        //           : _onEditPressed,
                                        //     ),
                                        //   if (canAddToAlbumCurrentItem)
                                        //     _buildBottomActionButton(
                                        //       palette: palette,
                                        //       icon: Icons.playlist_add_outlined,
                                        //       label: 'Add',
                                        //       isBusy: _isAddingCurrentItem,
                                        //       busyLabel: 'Adding...',
                                        //       onPressed:
                                        //           _isAnyBottomActionInProgress
                                        //           ? null
                                        //           : _onAddToAlbumPressed,
                                        //     ),
                                        //   if (canDeleteCurrentItem)
                                        //     _buildBottomActionButton(
                                        //       palette: palette,
                                        //       icon:
                                        //           Icons.delete_outline_rounded,
                                        //       label: 'Delete',
                                        //       isBusy: _isDeletingCurrentItem,
                                        //       busyLabel: 'Deleting...',
                                        //       onPressed:
                                        //           _isAnyBottomActionInProgress
                                        //           ? null
                                        //           : _onDeletePressed,
                                        //     ),
                                        // ],
                                        children: [
                                          _buildBottomActionButton(
                                            palette: palette,
                                            icon: Icons.bolt_rounded,
                                            label: quickActionsTexts
                                                .quickActionsButtonLabel,
                                            isBusy: false,
                                            busyLabel: quickActionsTexts
                                                .quickActionsButtonLabel,
                                            onPressed:
                                                _isAnyBottomActionInProgress
                                                ? null
                                                : () {
                                                    unawaited(
                                                      _showQuickActionsSheet(
                                                        canUploadCurrentItem:
                                                            canUploadCurrentItem,
                                                        canEditCurrentItem:
                                                            canEditCurrentItem,
                                                        canAddToAlbumCurrentItem:
                                                            canAddToAlbumCurrentItem,
                                                        canDeleteCurrentItem:
                                                            canDeleteCurrentItem,
                                                      ),
                                                    );
                                                  },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    // #new
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  double _resolveMediaAspectRatio(MediaItem item) {
    final double? fromMetadata = item.aspectRatio;
    if (fromMetadata != null && fromMetadata > 0) return fromMetadata;
    return 1.0;
  }
}

class _VerticalBarSliderThumbShape extends SliderComponentShape {
  const _VerticalBarSliderThumbShape({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size(width, height);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final Color color = ColorTween(
      begin: sliderTheme.disabledThumbColor,
      end: sliderTheme.thumbColor ?? Colors.white,
    ).evaluate(enableAnimation)!;
    final Paint paint = Paint()..color = color;
    final Rect rect = Rect.fromCenter(
      center: center,
      width: width,
      height: height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint,
    );
  }
}
