import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.widget.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/widgets/common/mesmerizing_sliver_app_bar.dart';

enum _VideoSourceFilter { all, cloudOnly, localOnly } // pizcloud

@RoutePage()
class DriftVideoPage extends ConsumerStatefulWidget {
  const DriftVideoPage({super.key});

  // pizcloud
  @override
  ConsumerState<DriftVideoPage> createState() => _DriftVideoPageState();
  // #pizcloud
}

class _DriftVideoPageState extends ConsumerState<DriftVideoPage> {
  _VideoSourceFilter _sourceFilter = _VideoSourceFilter.all; // pizcloud

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      key: ValueKey(_sourceFilter), // pizcloud
      overrides: [
        timelineServiceProvider.overrideWith((ref) {
          final user = ref.watch(currentUserProvider);
          if (user == null) {
            throw Exception('User must be logged in to video');
          }

          // pizcloud
          // final timelineService = ref.watch(timelineFactoryProvider).video(user.id, includeLocal: true);
          final timelineService = switch (_sourceFilter) {
            _VideoSourceFilter.all => ref.watch(timelineFactoryProvider).videoWithLocal(user.id),
            _VideoSourceFilter.cloudOnly => ref.watch(timelineFactoryProvider).video(user.id),
            _VideoSourceFilter.localOnly => ref.watch(timelineFactoryProvider).videoLocal(user.id),
          };
          // #pizcloud
          ref.onDispose(timelineService.dispose);
          return timelineService;
        }),
      ],
      // pizcloud
      child: Timeline(
        appBar: MesmerizingSliverAppBar(title: 'videos'.t()),
        topSliverWidget: SliverToBoxAdapter(
          child: _VideoSourceFilterBar(
            sourceFilter: _sourceFilter,
            onChanged: (filter) => setState(() => _sourceFilter = filter),
          ),
        ),
      ),
      // #pizcloud
    );
  }
}

// pizcloud
class _VideoSourceFilterBar extends StatelessWidget {
  final _VideoSourceFilter sourceFilter;
  final ValueChanged<_VideoSourceFilter> onChanged;

  const _VideoSourceFilterBar({required this.sourceFilter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: SegmentedButton<_VideoSourceFilter>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment<_VideoSourceFilter>(
            value: _VideoSourceFilter.all,
            label: Text('all'.t(context: context)),
            icon: const Icon(Icons.grid_view_rounded, size: 18),
          ),
          const ButtonSegment<_VideoSourceFilter>(
            value: _VideoSourceFilter.cloudOnly,
            label: Text('Cloud'),
            icon: Icon(Icons.cloud_outlined, size: 18),
          ),
          ButtonSegment<_VideoSourceFilter>(
            value: _VideoSourceFilter.localOnly,
            label: Text('on_this_device'.t(context: context)),
            icon: const Icon(Icons.phone_android_rounded, size: 18),
          ),
        ],
        selected: {sourceFilter},
        onSelectionChanged: (selected) {
          final nextFilter = selected.isEmpty ? null : selected.first;
          if (nextFilter == null || nextFilter == sourceFilter) {
            return;
          }
          onChanged(nextFilter);
        },
      ),
      // #pizcloud
    );
  }
}
