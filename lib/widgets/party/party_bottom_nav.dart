import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class PartyBottomNav extends StatelessWidget {
  final int selectedIndex;
  final int unreadMessages;
  final Function(int) onItemSelected;

  const PartyBottomNav({
    super.key,
    required this.selectedIndex,
    required this.unreadMessages,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.05),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _BottomNavItem(
            index: 0,
            icon: FontAwesomeIcons.list,
            label: "Queue",
            isSelected: selectedIndex == 0,
            onTap: () => onItemSelected(0),
          ),
          _BottomNavItem(
            index: 1,
            icon: FontAwesomeIcons.music,
            label: "Lyrics",
            isSelected: selectedIndex == 1,
            onTap: () => onItemSelected(1),
          ),
          _BottomNavItem(
            index: 2,
            icon: FontAwesomeIcons.solidComment,
            label: "Chat",
            isSelected: selectedIndex == 2,
            unreadCount: unreadMessages,
            onTap: () => onItemSelected(2),
          ),
        ],
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int unreadCount;

  const _BottomNavItem({
    required this.index,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.unreadCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? Theme.of(context).primaryColor
        : Colors.white.withValues(alpha: 0.4);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 20),
                if (unreadCount > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        unreadCount > 9 ? "9+" : "$unreadCount",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
