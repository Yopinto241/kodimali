import 'package:flutter/material.dart';

class ManageLanguageScope extends InheritedWidget {
  const ManageLanguageScope({super.key, required this.languageCode, required this.onChanged, required super.child});

  final String languageCode;
  final Future<void> Function(String languageCode) onChanged;

  static ManageLanguageScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ManageLanguageScope>();
    assert(scope != null, 'ManageLanguageScope not found');
    return scope!;
  }

  @override
  bool updateShouldNotify(ManageLanguageScope oldWidget) => languageCode != oldWidget.languageCode;
}

extension ManageLocalizationX on BuildContext {
  String get languageCode => ManageLanguageScope.of(this).languageCode;
  bool get isSwahili => languageCode == 'sw';
  Future<void> setLanguageCode(String value) => ManageLanguageScope.of(this).onChanged(value);

  String tr(String english) => isSwahili ? (_swahili[english] ?? english) : english;
}

const Map<String, String> _swahili = <String, String>{
  'Home': 'Nyumbani', 'Dashboard': 'Dashibodi', 'Listings': 'Matangazo',
  'Bookings': 'Booking', 'Chats': 'Mazungumzo', 'Profile': 'Wasifu',
  'Notifications': 'Arifa', 'Users': 'Watumiaji', 'Agents': 'Mawakala',
  'Categories': 'Makundi', 'Locations': 'Maeneo', 'Promotions': 'Promosheni',
  'Reports': 'Ripoti', 'Owners': 'Wamiliki', 'Assets': 'Mali',
  'Tenants': 'Wapangaji', 'Agreements': 'Mikataba', 'Statements': 'Taarifa za fedha',
  'Policies': 'Sera', 'Move-outs': 'Kuhama', 'Manage App': 'Programu ya Usimamizi',
  'Focused workspace': 'Sehemu yako ya kazi', 'Primary navigation': 'Urambazaji mkuu',
  'Focused workspace for listings, requests, approvals, and account activity.':
      'Sehemu ya kusimamia matangazo, maombi, idhini na shughuli za akaunti.',
  'Language': 'Lugha', 'Swahili': 'Kiswahili', 'English': 'Kiingereza',
  'WORKSPACE': 'SEHEMU YA KAZI',
};

class ManageLanguageButton extends StatelessWidget {
  const ManageLanguageButton({super.key});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: context.tr('Language'),
    icon: const Icon(Icons.language_rounded),
    initialValue: context.languageCode,
    onSelected: context.setLanguageCode,
    itemBuilder: (_) => <PopupMenuEntry<String>>[
      PopupMenuItem(value: 'sw', child: Text(context.tr('Swahili'))),
      PopupMenuItem(value: 'en', child: Text(context.tr('English'))),
    ],
  );
}
