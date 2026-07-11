import 'package:flutter/material.dart';
import 'package:ten_project_cua_ban/features/player/presentation/widgets/player_host.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Stack(children: [HomeScreen(), PlayerHost()]),
      bottomNavigationBar: HomeNavigationBar(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 20,
                        backgroundColor: Color(0xffffd2c5),
                        child: Icon(
                          Icons.person_rounded,
                          color: Color(0xff9a3412),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'ViListen',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Thông báo',
                        onPressed: () {},
                        icon: const Icon(Icons.notifications_none_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
                    children: const [
                      Text(
                        'Continue Learning',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 14),
                      _CourseCard(),
                      SizedBox(height: 30),
                      Text(
                        'New Releases',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 10),
                      _ReleaseTile(
                        title: 'Advanced Vocabulary',
                        subtitle: 'BBC Learning English • 5m',
                      ),
                      _ReleaseTile(
                        title: 'Tech Talk Weekly',
                        subtitle: 'ViUniverse Originals • 12m',
                      ),
                      _ReleaseTile(
                        title: 'Cultural Insights: Japan',
                        subtitle: 'Global Speak • 8m',
                      ),
                      _ReleaseTile(
                        title: 'Idioms & Phrases',
                        subtitle: 'Daily English • 4m',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard();

  @override
  Widget build(BuildContext context) => Container(
    height: 178,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xfff2542c), Color(0xffec4899)],
      ),
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33f2542c),
          blurRadius: 18,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          'Business English Basics',
          style: TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 5),
        Text(
          'Module 3 • Negotiation Skills',
          style: TextStyle(
            color: Color(0xfffff1ed),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _ReleaseTile extends StatelessWidget {
  const _ReleaseTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xffffa382), Color(0xffa855f7)],
        ),
      ),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.download_rounded, color: Color(0xff94a3b8)),
  );
}

class HomeNavigationBar extends StatelessWidget {
  const HomeNavigationBar({super.key});

  @override
  Widget build(BuildContext context) => NavigationBar(
    height: 64,
    selectedIndex: 0,
    onDestinationSelected: (_) {},
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    indicatorColor: Colors.transparent,
    elevation: 0,
    shadowColor: Colors.transparent,
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        fontSize: 10,
        fontWeight: states.contains(WidgetState.selected)
            ? FontWeight.w700
            : FontWeight.w500,
        color: states.contains(WidgetState.selected)
            ? const Color(0xfff2542c)
            : const Color(0xff94a3b8),
      ),
    ),
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.home_outlined, color: Color(0xff94a3b8)),
        selectedIcon: Icon(Icons.home_rounded, color: Color(0xfff2542c)),
        label: 'Home',
      ),
      NavigationDestination(
        icon: Icon(Icons.search_rounded, color: Color(0xff94a3b8)),
        selectedIcon: Icon(Icons.search_rounded, color: Color(0xfff2542c)),
        label: 'Explore',
      ),
      NavigationDestination(
        icon: Icon(Icons.school_rounded, color: Color(0xff94a3b8)),
        selectedIcon: Icon(Icons.school_rounded, color: Color(0xfff2542c)),
        label: 'My Plan',
      ),
      NavigationDestination(
        icon: Icon(Icons.person_outline_rounded, color: Color(0xff94a3b8)),
        selectedIcon: Icon(Icons.person_rounded, color: Color(0xfff2542c)),
        label: 'Profile',
      ),
    ],
  );
}
