import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    required this.currentLocation,
    required this.child,
    super.key,
  });

  final String currentLocation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppSection currentSection = _matchSection(currentLocation);

    return Scaffold(
      appBar: AppBar(
        title: Text(currentSection.label),
      ),
      body: SafeArea(child: child),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: AppSection.values.map((AppSection section) {
            final bool isSelected = section == currentSection;
            return _BottomNavButton(
              section: section,
              isSelected: isSelected,
              onTap: () => context.go(section.path),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }

  AppSection _matchSection(String location) {
    return AppSection.values.firstWhere(
      (AppSection section) => location.startsWith(section.path),
      orElse: () => AppSection.document,
    );
  }
}

class _BottomNavButton extends StatelessWidget {
  const _BottomNavButton({
    required this.section,
    required this.isSelected,
    required this.onTap,
  });

  final AppSection section;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(
        section.icon,
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      label: Text(
        section.label,
        style: TextStyle(
          color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}