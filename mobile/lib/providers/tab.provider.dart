import 'package:hooks_riverpod/hooks_riverpod.dart';

// Vesta: drive tab added
enum TabEnum { home, search, albums, library, drive }

/// Provides the currently active tab
final tabProvider = StateProvider<TabEnum>((ref) => TabEnum.home);
