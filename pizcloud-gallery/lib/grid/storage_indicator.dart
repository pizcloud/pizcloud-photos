import 'media_item.dart';

enum GridStorageIndicatorState { local, remote, merged }

typedef GridStorageIndicatorResolver =
    GridStorageIndicatorState? Function(MediaItem item);
