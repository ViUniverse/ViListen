import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ten_project_cua_ban/features/home/presentation/home_screen.dart';
import 'package:ten_project_cua_ban/features/player/presentation/cubit/player_cubit.dart';

void main() =>
    runApp(BlocProvider(create: (_) => PlayerCubit(), child: const MyApp()));

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
