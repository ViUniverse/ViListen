// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:vi_listen/app/player_bootstrap.dart';
import 'package:vi_listen/features/home/presentation/home_screen.dart';

Future<void> main() async {
  await startPlayerApplication(app: const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ViListen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xfff8f6f5),
        fontFamily: 'Inter',
      ),
      home: const AppShell(),
    );
  }
}
