import 'package:hooks_riverpod/hooks_riverpod.dart';

// pizcloud
// enum TabEnum { home, search, albums, library }
enum TabEnum { newLibrary, backup, albums, settings } // pizcloud

/// Provides the currently active tab
final tabProvider = StateProvider<TabEnum>((ref) => TabEnum.newLibrary); // pizcloud
