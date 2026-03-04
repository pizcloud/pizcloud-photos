import 'package:hooks_riverpod/hooks_riverpod.dart';

// pizcloud
// enum TabEnum { home, search, albums, library }
enum TabEnum { home, search, albums, library, newLibrary } // pizcloud

/// Provides the currently active tab
final tabProvider = StateProvider<TabEnum>((ref) => TabEnum.home);
