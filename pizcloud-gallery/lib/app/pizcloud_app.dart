import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';

import '../features/home/pizcloud_home.dart';

class PizCloudApp extends StatelessWidget {
  const PizCloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return PlatformApp(
      title: 'PizCloud Photos',
      debugShowCheckedModeBanner: false,
      material: (_, __) => MaterialAppData(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
          scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        ),
      ),
      cupertino: (_, __) => CupertinoAppData(
        theme: const CupertinoThemeData(
          brightness: Brightness.light,
          primaryColor: CupertinoColors.activeBlue,
          barBackgroundColor: Color.fromARGB(255, 0, 0, 0),
        ),
      ),
      home: const PizCloudHomePage(),
    );
  }
}
