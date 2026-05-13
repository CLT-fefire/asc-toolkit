import 'package:flutter/material.dart';

import 'screens/teams_screen.dart';
import 'services/team_repository.dart';

void main() {
  runApp(const AscToolkitApp());
}

class AscToolkitApp extends StatelessWidget {
  const AscToolkitApp({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = TeamRepository();
    return MaterialApp(
      title: 'ASC Toolkit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3C6CFF)),
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: TeamsScreen(repository: repository),
    );
  }
}
