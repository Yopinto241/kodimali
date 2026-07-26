import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/cache/customer_activity_store.dart';
import '../../core/data/customer_account_repository.dart';
import '../../core/data/customer_public_repository.dart';
import '../../core/localization/customer_localization.dart';

typedef OpenCustomerListing = void Function(String listingId);

String _accountError(Object error) => error
    .toString()
    .replaceFirst('Bad state: ', '')
    .replaceFirst('Exception: ', '')
    .trim();

Map<String, dynamic> _relatedMap(dynamic value) {
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  if (value is List && value.isNotEmpty && value.first is Map) {
    return (value.first as Map).cast<String, dynamic>();
  }
  return <String, dynamic>{};
}

String _formatCustomerDate(BuildContext context, dynamic value) {
  final DateTime? date = value is DateTime
      ? value
      : DateTime.tryParse(value?.toString() ?? '');
  if (date == null) {
    return '-';
  }
  final MaterialLocalizations localizations = MaterialLocalizations.of(context);
  final DateTime local = date.toLocal();
  return '${localizations.formatMediumDate(local)} · '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

String _bookingStatusLabel(BuildContext context, String status) {
  final String key = 'booking.status.$status';
  final String translated = context.tr(key);
  if (translated != key) {
    return translated;
  }
  return status.replaceAll('_', ' ');
}

KodimaliStatusTone _bookingStatusTone(String status) {
  return switch (status) {
    'completed' || 'confirmed' => KodimaliStatusTone.active,
    'cancelled' || 'rejected' || 'no_response' => KodimaliStatusTone.danger,
    'contacted' || 'viewing_scheduled' || 'reserved' => KodimaliStatusTone.info,
    _ => KodimaliStatusTone.pending,
  };
}

class CustomerAccountScreen extends StatefulWidget {
  const CustomerAccountScreen({
    super.key,
    required this.accountRepository,
    required this.publicRepository,
    required this.onOpenListing,
  });

  final CustomerAccountRepository accountRepository;
  final CustomerPublicRepository publicRepository;
  final OpenCustomerListing onOpenListing;

  @override
  State<CustomerAccountScreen> createState() => _CustomerAccountScreenState();
}

class _CustomerAccountScreenState extends State<CustomerAccountScreen> {
  StreamSubscription<AuthState>? _authSubscription;
  Future<Map<String, dynamic>>? _profileFuture;
  bool _syncingSaved = false;

  bool get _signedIn => widget.accountRepository.isSignedIn;

  @override
  void initState() {
    super.initState();
    _profileFuture = widget.accountRepository.fetchMyProfile();
    _authSubscription = widget.accountRepository.authStateChanges.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _profileFuture = widget.accountRepository.fetchMyProfile();
      });
      unawaited(_synchronizeSavedListings());
    });
    unawaited(_synchronizeSavedListings());
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _profileFuture = widget.accountRepository.fetchMyProfile();
    });
    await _synchronizeSavedListings();
    await _profileFuture;
  }

  Future<void> _synchronizeSavedListings() async {
    if (!_signedIn || _syncingSaved) {
      return;
    }
    _syncingSaved = true;
    try {
      final CustomerActivityStore activity = CustomerActivityStore.instance;
      final Set<String> localIds = activity.savedListingIds;
      final Set<String> remoteIds = await widget.accountRepository
          .fetchRemoteSavedListingIds();
      for (final String listingId in localIds.difference(remoteIds)) {
        await widget.accountRepository.saveListing(listingId);
      }
      await activity.setSavedFromRemote(<String>{...localIds, ...remoteIds});
    } catch (_) {
      // Local favourites remain available when sync is temporarily unavailable.
    } finally {
      _syncingSaved = false;
    }
  }

  Future<void> _openAuth({required bool createAccount}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CustomerAuthScreen(
          repository: widget.accountRepository,
          createAccountInitially: createAccount,
        ),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _signOut() async {
    await widget.accountRepository.signOut();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('account.signedOut'))));
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            CustomerSettingsScreen(repository: widget.accountRepository),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _requestAccountDeletion() async {
    final TextEditingController reasonController = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(context.tr('account.deleteTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.tr('account.deleteBody')),
            const SizedBox(height: KodimaliSpacing.md),
            TextField(
              controller: reasonController,
              maxLength: 1000,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: context.tr('account.deleteReason'),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('account.deleteConfirm')),
          ),
        ],
      ),
    );
    final String reason = reasonController.text;
    reasonController.dispose();
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.accountRepository.requestAccountDeletion(reason: reason);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('account.deleteSubmitted'))),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_accountError(error))));
      }
    }
  }

  Future<void> _claimRequest() async {
    final TextEditingController controller = TextEditingController();
    final String? reference = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(context.tr('requests.claimTitle')),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: context.tr('requests.reference'),
            helperText: context.tr('requests.claimHelp'),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(context.tr('requests.claimAction')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reference == null || reference.trim().isEmpty || !mounted) {
      return;
    }
    try {
      await widget.accountRepository.claimGuestRequest(reference);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('requests.claimed'))));
      _openRequests();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_accountError(error))));
      }
    }
  }

  void _openRequests() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerRequestsScreen(
          accountRepository: widget.accountRepository,
          onOpenListing: widget.onOpenListing,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        key: const PageStorageKey<String>('customer_account'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: KodimaliSpacing.screenPadding,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.tr('account.title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const _AccountLanguageButton(),
            ],
          ),
          const SizedBox(height: KodimaliSpacing.md),
          if (_signedIn)
            FutureBuilder<Map<String, dynamic>>(
              future: _profileFuture,
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<Map<String, dynamic>> snapshot,
                  ) {
                    final Map<String, dynamic> profile =
                        snapshot.data ?? <String, dynamic>{};
                    final String name =
                        profile['full_name']?.toString().trim() ?? '';
                    final String email =
                        profile['account_email']?.toString() ??
                        widget.accountRepository.currentUser?.email ??
                        '';
                    return _AccountWelcomeCard(
                      signedIn: true,
                      title: name.isEmpty
                          ? context.tr('account.customer')
                          : name,
                      subtitle: email,
                      onPrimary: _openRequests,
                      onSecondary: _signOut,
                    );
                  },
            )
          else
            _AccountWelcomeCard(
              signedIn: false,
              title: context.tr('account.optionalTitle'),
              subtitle: context.tr('account.optionalBody'),
              onPrimary: () => _openAuth(createAccount: false),
              onSecondary: () => _openAuth(createAccount: true),
            ),
          if (_signedIn) ...<Widget>[
            const SizedBox(height: KodimaliSpacing.sm),
            OutlinedButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
              label: Text(context.tr('settings.title')),
            ),
            const SizedBox(height: KodimaliSpacing.xs),
            OutlinedButton.icon(
              onPressed: _claimRequest,
              icon: const Icon(Icons.link_rounded),
              label: Text(context.tr('requests.claimTitle')),
            ),
            const SizedBox(height: KodimaliSpacing.xs),
            TextButton.icon(
              onPressed: _requestAccountDeletion,
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(context.tr('account.deleteAction')),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: KodimaliSpacing.lg),
          _ActivitySection(
            title: context.tr('saved.title'),
            emptyMessage: context.tr('saved.empty'),
            activityListenable: CustomerActivityStore.instance,
            listings: () => CustomerActivityStore.instance.savedListings,
            publicRepository: widget.publicRepository,
            onOpenListing: widget.onOpenListing,
          ),
          const SizedBox(height: KodimaliSpacing.lg),
          _ActivitySection(
            title: context.tr('recent.title'),
            emptyMessage: context.tr('recent.empty'),
            activityListenable: CustomerActivityStore.instance,
            listings: () => CustomerActivityStore.instance.recentlyViewed,
            publicRepository: widget.publicRepository,
            onOpenListing: widget.onOpenListing,
            trailing: TextButton(
              onPressed: CustomerActivityStore.instance.recentlyViewed.isEmpty
                  ? null
                  : () => CustomerActivityStore.instance.clearRecentlyViewed(),
              child: Text(context.tr('recent.clear')),
            ),
          ),
          const SizedBox(height: 96),
        ],
      ),
    );
  }
}

class _AccountWelcomeCard extends StatelessWidget {
  const _AccountWelcomeCard({
    required this.signedIn,
    required this.title,
    required this.subtitle,
    required this.onPrimary,
    required this.onSecondary,
  });

  final bool signedIn;
  final String title;
  final String subtitle;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(KodimaliSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CircleAvatar(
              radius: 26,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                signedIn ? Icons.person_rounded : Icons.person_outline_rounded,
              ),
            ),
            const SizedBox(height: KodimaliSpacing.md),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: KodimaliSpacing.xs),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: KodimaliSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onPrimary,
                    icon: Icon(
                      signedIn
                          ? Icons.receipt_long_rounded
                          : Icons.login_rounded,
                    ),
                    label: Text(
                      context.tr(signedIn ? 'requests.my' : 'account.signIn'),
                    ),
                  ),
                ),
                const SizedBox(width: KodimaliSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onSecondary,
                    child: Text(
                      context.tr(
                        signedIn ? 'account.signOut' : 'account.create',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({
    required this.title,
    required this.emptyMessage,
    required this.activityListenable,
    required this.listings,
    required this.publicRepository,
    required this.onOpenListing,
    this.trailing,
  });

  final String title;
  final String emptyMessage;
  final Listenable activityListenable;
  final List<Map<String, dynamic>> Function() listings;
  final CustomerPublicRepository publicRepository;
  final OpenCustomerListing onOpenListing;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: activityListenable,
      builder: (BuildContext context, _) {
        final List<Map<String, dynamic>> items = listings();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: KodimaliSpacing.sm),
            if (items.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(KodimaliSpacing.md),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.bookmark_border_rounded),
                      const SizedBox(width: KodimaliSpacing.sm),
                      Expanded(child: Text(emptyMessage)),
                    ],
                  ),
                ),
              )
            else
              ...items
                  .take(8)
                  .map(
                    (Map<String, dynamic> listing) => Padding(
                      padding: const EdgeInsets.only(
                        bottom: KodimaliSpacing.sm,
                      ),
                      child: _ActivityListingTile(
                        snapshot: listing,
                        repository: publicRepository,
                        onOpenListing: onOpenListing,
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }
}

class _ActivityListingTile extends StatelessWidget {
  const _ActivityListingTile({
    required this.snapshot,
    required this.repository,
    required this.onOpenListing,
  });

  final Map<String, dynamic> snapshot;
  final CustomerPublicRepository repository;
  final OpenCustomerListing onOpenListing;

  @override
  Widget build(BuildContext context) {
    final String listingId = (snapshot['listing_id'] ?? snapshot['id'] ?? '')
        .toString();
    final String snapshotTitle = snapshot['title']?.toString() ?? '';
    if (snapshotTitle.isNotEmpty) {
      return _listingTile(context, snapshot, listingId);
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: repository.fetchListingDetail(listingId),
      builder:
          (BuildContext context, AsyncSnapshot<Map<String, dynamic>> detail) =>
              _listingTile(
                context,
                detail.data ?? snapshot,
                listingId,
                loading: detail.connectionState == ConnectionState.waiting,
              ),
    );
  }

  Widget _listingTile(
    BuildContext context,
    Map<String, dynamic> listing,
    String listingId, {
    bool loading = false,
  }) {
    final String title = listing['title']?.toString().trim() ?? '';
    final String location =
        listing['public_location_label']?.toString().trim() ?? '';
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            loading ? Icons.hourglass_top_rounded : Icons.home_work_outlined,
          ),
        ),
        title: Text(title.isEmpty ? context.tr('listing.details') : title),
        subtitle: location.isEmpty ? null : Text(location),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: listingId.isEmpty ? null : () => onOpenListing(listingId),
      ),
    );
  }
}

class CustomerAuthScreen extends StatefulWidget {
  const CustomerAuthScreen({
    super.key,
    required this.repository,
    this.createAccountInitially = false,
  });

  final CustomerAccountRepository repository;
  final bool createAccountInitially;

  @override
  State<CustomerAuthScreen> createState() => _CustomerAuthScreenState();
}

class _CustomerAuthScreenState extends State<CustomerAuthScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late bool _createAccount = widget.createAccountInitially;
  bool _submitting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    try {
      if (_createAccount) {
        final AuthResponse response = await widget.repository.signUp(
          fullName: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          phoneNumber: _phoneController.text,
          preferredLanguage: context.languageCode,
        );
        if (!mounted) {
          return;
        }
        if (response.session == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('account.confirmEmail'))),
          );
          setState(() => _createAccount = false);
          return;
        }
      } else {
        await widget.repository.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_accountError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _forgotPassword() async {
    final String email = _emailController.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('request.emailError'))));
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.repository.sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('password.resetSent'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_accountError(error))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(_createAccount ? 'account.create' : 'account.signIn'),
        ),
        actions: const <Widget>[_AccountLanguageButton()],
      ),
      body: SafeArea(
        child: ListView(
          padding: KodimaliSpacing.screenPadding,
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(KodimaliSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      _createAccount
                          ? Icons.person_add_alt_1_rounded
                          : Icons.lock_open_rounded,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: KodimaliSpacing.md),
                    Text(
                      context.tr(
                        _createAccount
                            ? 'account.createTitle'
                            : 'account.signInTitle',
                      ),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: KodimaliSpacing.xs),
                    Text(context.tr('account.guestStillWorks')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: KodimaliSpacing.md),
            Form(
              key: _formKey,
              child: Column(
                children: <Widget>[
                  if (_createAccount) ...<Widget>[
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: context.tr('request.fullName'),
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                      ),
                      validator: (String? value) =>
                          (value?.trim().length ?? 0) < 2
                          ? context.tr('request.nameError')
                          : null,
                    ),
                    const SizedBox(height: KodimaliSpacing.md),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: context.tr('request.phoneOptional'),
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                      validator: (String? value) {
                        final String phone = value?.trim() ?? '';
                        return phone.isNotEmpty && phone.length < 8
                            ? context.tr('request.phoneError')
                            : null;
                      },
                    ),
                    const SizedBox(height: KodimaliSpacing.md),
                  ],
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: context.tr('request.email'),
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                    validator: (String? value) =>
                        RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(value?.trim() ?? '')
                        ? null
                        : context.tr('request.emailError'),
                  ),
                  const SizedBox(height: KodimaliSpacing.md),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: context.tr('account.password'),
                      prefixIcon: const Icon(Icons.password_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (String? value) => (value?.length ?? 0) < 8
                        ? context.tr('account.passwordError')
                        : null,
                    onFieldSubmitted: (_) => _submitting ? null : _submit(),
                  ),
                  if (!_createAccount)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _submitting ? null : _forgotPassword,
                        child: Text(context.tr('password.forgot')),
                      ),
                    ),
                  const SizedBox(height: KodimaliSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text(
                        _submitting
                            ? context.tr('request.submitting')
                            : context.tr(
                                _createAccount
                                    ? 'account.create'
                                    : 'account.signIn',
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: KodimaliSpacing.sm),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () =>
                              setState(() => _createAccount = !_createAccount),
                    child: Text(
                      context.tr(
                        _createAccount
                            ? 'account.haveAccount'
                            : 'account.needAccount',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerSettingsScreen extends StatefulWidget {
  const CustomerSettingsScreen({super.key, required this.repository});
  final CustomerAccountRepository repository;

  @override
  State<CustomerSettingsScreen> createState() => _CustomerSettingsScreenState();
}

class _CustomerSettingsScreenState extends State<CustomerSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await widget.repository.fetchMyProfile();
    if (!mounted) return;
    _name.text = profile['full_name']?.toString() ?? '';
    _phone.text = profile['phone_number']?.toString() ?? '';
    setState(() => _loading = false);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.repository.updateProfile(
        fullName: _name.text,
        phoneNumber: _phone.text,
        preferredLanguage: context.languageCode,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('settings.saved'))));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_accountError(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    if (_password.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('account.passwordError'))),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.changePassword(_password.text);
      _password.clear();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('password.changed'))));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_accountError(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('settings.title'))),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: KodimaliSpacing.screenPadding,
            children: <Widget>[
              Text(
                context.tr('settings.appearance'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: <ButtonSegment<ThemeMode>>[
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: const Icon(Icons.settings_suggest_outlined),
                    label: Text(context.tr('theme.system')),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(Icons.light_mode_outlined),
                    label: Text(context.tr('theme.light')),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(Icons.dark_mode_outlined),
                    label: Text(context.tr('theme.dark')),
                  ),
                ],
                selected: <ThemeMode>{context.themeMode},
                onSelectionChanged: (value) =>
                    context.setThemeMode(value.first),
              ),
              const SizedBox(height: 24),
              Text(
                context.tr('settings.profile'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Form(
                key: _formKey,
                child: Column(
                  children: <Widget>[
                    TextFormField(
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: context.tr('request.fullName'),
                      ),
                      validator: (v) => (v?.trim().length ?? 0) < 2
                          ? context.tr('request.nameError')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: context.tr('request.phoneOptional'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _saveProfile,
                        child: Text(context.tr('settings.save')),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.tr('password.change'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.tr('password.new'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _saving ? null : _changePassword,
                child: Text(context.tr('password.change')),
              ),
            ],
          ),
  );
}

class CustomerPasswordResetScreen extends StatefulWidget {
  const CustomerPasswordResetScreen({super.key, required this.repository});
  final CustomerAccountRepository repository;
  @override
  State<CustomerPasswordResetScreen> createState() =>
      _CustomerPasswordResetScreenState();
}

class _CustomerPasswordResetScreenState
    extends State<CustomerPasswordResetScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 8) return;
    setState(() => _busy = true);
    try {
      await widget.repository.changePassword(_password.text);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('password.changed'))));
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_accountError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('password.reset'))),
    body: ListView(
      padding: KodimaliSpacing.screenPadding,
      children: <Widget>[
        Text(context.tr('password.resetHelp')),
        const SizedBox(height: 16),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: InputDecoration(labelText: context.tr('password.new')),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(context.tr('password.save')),
        ),
      ],
    ),
  );
}

class CustomerRequestsScreen extends StatefulWidget {
  const CustomerRequestsScreen({
    super.key,
    required this.accountRepository,
    required this.onOpenListing,
  });

  final CustomerAccountRepository accountRepository;
  final OpenCustomerListing onOpenListing;

  @override
  State<CustomerRequestsScreen> createState() => _CustomerRequestsScreenState();
}

class _CustomerRequestsScreenState extends State<CustomerRequestsScreen> {
  static const Duration _refreshInterval = Duration(seconds: 15);
  Future<List<Map<String, dynamic>>>? _requestsFuture;
  Timer? _refreshTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _requestUpdates;

  @override
  void initState() {
    super.initState();
    _reload();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _reload());
    _requestUpdates = widget.accountRepository
        .watchMyBookingRequestChanges()
        .listen((_) => _reload(), onError: (_) {});
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    unawaited(_requestUpdates?.cancel());
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) {
      return;
    }
    final Future<List<Map<String, dynamic>>> future = widget.accountRepository
        .fetchMyBookingRequests();
    setState(() => _requestsFuture = future);
    try {
      await future;
    } catch (_) {
      // FutureBuilder presents the actionable error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('requests.my')),
        actions: <Widget>[
          IconButton(
            onPressed: _reload,
            tooltip: context.tr('location.retry'),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const _AccountLanguageButton(),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _requestsFuture,
        builder:
            (
              BuildContext context,
              AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
            ) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _AccountErrorView(
                  message: _accountError(snapshot.error!),
                  onRetry: _reload,
                );
              }
              final List<Map<String, dynamic>> requests =
                  snapshot.data ?? <Map<String, dynamic>>[];
              if (requests.isEmpty) {
                return _AccountEmptyView(
                  icon: Icons.receipt_long_outlined,
                  title: context.tr('requests.emptyTitle'),
                  body: context.tr('requests.emptyBody'),
                );
              }
              return RefreshIndicator(
                onRefresh: _reload,
                child: ListView.separated(
                  padding: KodimaliSpacing.screenPadding,
                  itemCount: requests.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: KodimaliSpacing.sm),
                  itemBuilder: (BuildContext context, int index) {
                    final Map<String, dynamic> request = requests[index];
                    return _CustomerRequestCard(
                      request: request,
                      onOpen: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CustomerRequestDetailScreen(
                            bookingRequestId: request['id'].toString(),
                            repository: widget.accountRepository,
                            onOpenListing: widget.onOpenListing,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
      ),
    );
  }
}

class _CustomerRequestCard extends StatelessWidget {
  const _CustomerRequestCard({required this.request, required this.onOpen});

  final Map<String, dynamic> request;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> listing = _relatedMap(request['listings']);
    final Map<String, dynamic> agent = _relatedMap(request['agents']);
    final String status = request['booking_status']?.toString() ?? 'new';
    final String agentName =
        request['agent_display_name']?.toString() ??
        request['agent_business_name']?.toString() ??
        agent['display_name']?.toString() ??
        agent['business_name']?.toString() ??
        context.tr('requests.assignedAgent');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(KodimaliRadii.card),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(KodimaliSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      request['listing_title']?.toString() ??
                          listing['title']?.toString() ??
                          context.tr('listing.details'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  KodimaliStatusBadge(
                    label: _bookingStatusLabel(context, status),
                    tone: _bookingStatusTone(status),
                  ),
                ],
              ),
              const SizedBox(height: KodimaliSpacing.sm),
              Text('${context.tr('requests.agent')}: $agentName'),
              const SizedBox(height: 4),
              Text(
                '${context.tr('requests.reference')}: '
                '${request['request_reference'] ?? '-'}',
              ),
              const SizedBox(height: 4),
              Text(_formatCustomerDate(context, request['created_at'])),
              const SizedBox(height: KodimaliSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.timeline_rounded),
                  label: Text(context.tr('requests.track')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerRequestDetailScreen extends StatefulWidget {
  const CustomerRequestDetailScreen({
    super.key,
    required this.bookingRequestId,
    required this.repository,
    required this.onOpenListing,
  });

  final String bookingRequestId;
  final CustomerAccountRepository repository;
  final OpenCustomerListing onOpenListing;

  @override
  State<CustomerRequestDetailScreen> createState() =>
      _CustomerRequestDetailScreenState();
}

class _CustomerRequestDetailScreenState
    extends State<CustomerRequestDetailScreen> {
  Future<_CustomerRequestDetailData>? _future;
  StreamSubscription<List<Map<String, dynamic>>>? _bookingUpdates;
  StreamSubscription<List<Map<String, dynamic>>>? _appointmentUpdates;

  @override
  void initState() {
    super.initState();
    _reload();
    _bookingUpdates = widget.repository
        .watchBookingRequestChanges(widget.bookingRequestId)
        .listen((_) => _reload(), onError: (_) {});
    _appointmentUpdates = widget.repository
        .watchViewingAppointmentChanges(widget.bookingRequestId)
        .listen((_) => _reload(), onError: (_) {});
  }

  @override
  void dispose() {
    unawaited(_bookingUpdates?.cancel());
    unawaited(_appointmentUpdates?.cancel());
    super.dispose();
  }

  Future<void> _reload() async {
    final Future<_CustomerRequestDetailData> future = _loadData();
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {
      // FutureBuilder shows the error.
    }
  }

  Future<_CustomerRequestDetailData> _loadData() async {
    final String notFoundMessage = context.tr('requests.notFound');
    final Map<String, dynamic>? request = await widget.repository
        .fetchBookingRequest(widget.bookingRequestId);
    if (request == null) {
      throw StateError(notFoundMessage);
    }
    final List<dynamic> extras = await Future.wait<dynamic>(<Future<dynamic>>[
      widget.repository.fetchBookingHistory(widget.bookingRequestId),
      widget.repository.fetchViewingAppointments(widget.bookingRequestId),
      if (request['booking_status'] == 'completed')
        widget.repository.fetchMyReview(widget.bookingRequestId)
      else
        Future<Map<String, dynamic>?>.value(null),
    ]);
    return _CustomerRequestDetailData(
      request: request,
      history: (extras[0] as List).cast<Map<String, dynamic>>(),
      appointments: (extras[1] as List).cast<Map<String, dynamic>>(),
      review: extras[2] as Map<String, dynamic>?,
    );
  }

  Future<void> _openChat(Map<String, dynamic> request) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CustomerAgentChatScreen(
          bookingRequestId: widget.bookingRequestId,
          repository: widget.repository,
          agentName:
              request['agent_display_name']?.toString() ??
              request['agent_business_name']?.toString() ??
              _relatedMap(request['agents'])['display_name']?.toString() ??
              context.tr('requests.assignedAgent'),
        ),
      ),
    );
  }

  Future<void> _scheduleViewing() async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CustomerViewingAppointmentScreen(
          bookingRequestId: widget.bookingRequestId,
          repository: widget.repository,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _reload();
    }
  }

  Future<void> _respondToViewingAppointment(
    Map<String, dynamic> appointment,
    String status,
  ) async {
    if (status == 'cancelled') {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(context.tr('viewing.cancel')),
          content: Text(context.tr('viewing.cancelConfirm')),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.tr('viewing.cancel')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    try {
      await widget.repository.respondToViewingAppointment(
        appointmentId: appointment['id'].toString(),
        status: status,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('viewing.updated'))));
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_accountError(error))));
      }
    }
  }

  Future<void> _writeReview(Map<String, dynamic>? existingReview) async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CustomerReviewScreen(
          bookingRequestId: widget.bookingRequestId,
          repository: widget.repository,
          existingReview: existingReview,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('requests.track')),
        actions: <Widget>[
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const _AccountLanguageButton(),
        ],
      ),
      body: FutureBuilder<_CustomerRequestDetailData>(
        future: _future,
        builder:
            (
              BuildContext context,
              AsyncSnapshot<_CustomerRequestDetailData> snapshot,
            ) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return _AccountErrorView(
                  message: _accountError(snapshot.error ?? 'Request not found'),
                  onRetry: _reload,
                );
              }
              final _CustomerRequestDetailData data = snapshot.data!;
              return _buildDetail(context, data);
            },
      ),
    );
  }

  Widget _buildDetail(BuildContext context, _CustomerRequestDetailData data) {
    final Map<String, dynamic> request = data.request;
    final Map<String, dynamic> listing = _relatedMap(request['listings']);
    final Map<String, dynamic> agent = _relatedMap(request['agents']);
    final String status = request['booking_status']?.toString() ?? 'new';
    final bool canSchedule = !<String>{
      'completed',
      'cancelled',
      'rejected',
      'no_response',
    }.contains(status);
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: KodimaliSpacing.screenPadding,
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(KodimaliSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  KodimaliStatusBadge(
                    label: _bookingStatusLabel(context, status),
                    tone: _bookingStatusTone(status),
                  ),
                  const SizedBox(height: KodimaliSpacing.sm),
                  Text(
                    request['listing_title']?.toString() ??
                        listing['title']?.toString() ??
                        context.tr('listing.details'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: KodimaliSpacing.xs),
                  Text(
                    '${context.tr('requests.reference')}: '
                    '${request['request_reference'] ?? '-'}',
                  ),
                  const SizedBox(height: KodimaliSpacing.md),
                  Wrap(
                    spacing: KodimaliSpacing.sm,
                    runSpacing: KodimaliSpacing.sm,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: () => widget.onOpenListing(
                          request['listing_id'].toString(),
                        ),
                        icon: const Icon(Icons.home_work_outlined),
                        label: Text(context.tr('requests.openListing')),
                      ),
                      FilledButton.icon(
                        onPressed: () => _openChat(request),
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        label: Text(context.tr('chat.title')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: KodimaliSpacing.md),
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.support_agent_rounded),
              ),
              title: Text(
                request['agent_display_name']?.toString() ??
                    request['agent_business_name']?.toString() ??
                    agent['display_name']?.toString() ??
                    agent['business_name']?.toString() ??
                    context.tr('requests.assignedAgent'),
              ),
              subtitle: Text(context.tr('requests.chatOnlyAssigned')),
              trailing: const Icon(Icons.chat_outlined),
              onTap: () => _openChat(request),
            ),
          ),
          const SizedBox(height: KodimaliSpacing.lg),
          Text(
            context.tr('requests.progress'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: KodimaliSpacing.sm),
          _BookingTimeline(history: data.history, currentStatus: status),
          const SizedBox(height: KodimaliSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.tr('viewing.title'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (canSchedule)
                TextButton.icon(
                  onPressed: _scheduleViewing,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(context.tr('viewing.propose')),
                ),
            ],
          ),
          if (data.appointments.isEmpty)
            Text(context.tr('viewing.empty'))
          else
            ...data.appointments.map((Map<String, dynamic> appointment) {
              final String appointmentStatus =
                  appointment['status']?.toString() ?? 'proposed';
              final bool active = <String>{
                'proposed',
                'confirmed',
                'reschedule_requested',
              }.contains(appointmentStatus);
              final bool canConfirm =
                  <String>{
                    'proposed',
                    'reschedule_requested',
                  }.contains(appointmentStatus) &&
                  appointment['proposed_by'] !=
                      widget.repository.currentUser?.id;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: KodimaliSpacing.xs),
                  child: Column(
                    children: <Widget>[
                      ListTile(
                        leading: const Icon(Icons.event_available_outlined),
                        title: Text(
                          _formatCustomerDate(
                            context,
                            appointment['scheduled_start_at'],
                          ),
                        ),
                        subtitle: Text(
                          '${_bookingStatusLabel(context, appointmentStatus)}'
                          '${appointment['location_note'] == null ? '' : '\n${appointment['location_note']}'}'
                          '${appointment['response_note'] == null ? '' : '\n${appointment['response_note']}'}',
                        ),
                        isThreeLine:
                            appointment['location_note'] != null ||
                            appointment['response_note'] != null,
                      ),
                      if (active)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              TextButton(
                                onPressed: () => _respondToViewingAppointment(
                                  appointment,
                                  'cancelled',
                                ),
                                child: Text(context.tr('viewing.cancel')),
                              ),
                              if (canConfirm)
                                FilledButton(
                                  onPressed: () => _respondToViewingAppointment(
                                    appointment,
                                    'confirmed',
                                  ),
                                  child: Text(context.tr('viewing.confirm')),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          if (status == 'completed') ...<Widget>[
            const SizedBox(height: KodimaliSpacing.lg),
            Card(
              child: ListTile(
                leading: const Icon(Icons.star_outline_rounded),
                title: Text(
                  data.review == null
                      ? context.tr('review.title')
                      : context.tr('review.thanks'),
                ),
                subtitle: data.review == null
                    ? Text(context.tr('review.completedOnly'))
                    : Text(
                        '${data.review!['rating']} / 5'
                        '${data.review!['comment'] == null ? '' : ' · ${data.review!['comment']}'}',
                      ),
                trailing: data.review == null
                    ? const Icon(Icons.chevron_right_rounded)
                    : null,
                onTap: data.review == null ? () => _writeReview(null) : null,
              ),
            ),
          ],
          const SizedBox(height: 72),
        ],
      ),
    );
  }
}

class _BookingTimeline extends StatelessWidget {
  const _BookingTimeline({required this.history, required this.currentStatus});

  final List<Map<String, dynamic>> history;
  final String currentStatus;

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> rows = history.isEmpty
        ? <Map<String, dynamic>>[
            <String, dynamic>{'status': currentStatus},
          ]
        : history;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(KodimaliSpacing.md),
        child: Column(
          children: List<Widget>.generate(rows.length, (int index) {
            final Map<String, dynamic> item = rows[index];
            final String status = item['status']?.toString() ?? 'new';
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Column(
                  children: <Widget>[
                    Icon(
                      index == rows.length - 1
                          ? Icons.radio_button_checked_rounded
                          : Icons.check_circle_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    if (index != rows.length - 1)
                      Container(
                        width: 2,
                        height: 38,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                  ],
                ),
                const SizedBox(width: KodimaliSpacing.sm),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _bookingStatusLabel(context, status),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (item['created_at'] != null)
                          Text(
                            _formatCustomerDate(context, item['created_at']),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if ((item['reason']?.toString().trim() ?? '')
                            .isNotEmpty)
                          Text(item['reason'].toString()),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class CustomerAgentChatScreen extends StatefulWidget {
  const CustomerAgentChatScreen({
    super.key,
    required this.bookingRequestId,
    required this.repository,
    required this.agentName,
  });

  final String bookingRequestId;
  final CustomerAccountRepository repository;
  final String agentName;

  @override
  State<CustomerAgentChatScreen> createState() =>
      _CustomerAgentChatScreenState();
}

class _CustomerAgentChatScreenState extends State<CustomerAgentChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Future<Map<String, dynamic>>? _conversationFuture;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _conversationFuture = widget.repository.getOrCreateConversation(
      widget.bookingRequestId,
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String conversationId) async {
    final String body = _messageController.text.trim();
    if (body.isEmpty || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.repository.sendMessage(
        conversationId: conversationId,
        body: body,
        clientMessageId: _newUuid(),
      );
      _messageController.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_accountError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  String _newUuid() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final String hex = bytes
        .map((int value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.tr('chat.title')),
            Text(
              widget.agentName,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _conversationFuture,
        builder:
            (
              BuildContext context,
              AsyncSnapshot<Map<String, dynamic>> conversation,
            ) {
              if (conversation.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (conversation.hasError || !conversation.hasData) {
                return _AccountErrorView(
                  message: _accountError(
                    conversation.error ?? 'Chat unavailable',
                  ),
                  onRetry: () => setState(
                    () => _conversationFuture = widget.repository
                        .getOrCreateConversation(widget.bookingRequestId),
                  ),
                );
              }
              final String conversationId = conversation.data!['id'].toString();
              unawaited(widget.repository.markConversationRead(conversationId));
              return Column(
                children: <Widget>[
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: widget.repository.watchMessages(conversationId),
                      builder:
                          (
                            BuildContext context,
                            AsyncSnapshot<List<Map<String, dynamic>>> messages,
                          ) {
                            if (messages.hasError) {
                              return _AccountErrorView(
                                message: context.tr('chat.unavailable'),
                                onRetry: () => setState(() {}),
                              );
                            }
                            final List<Map<String, dynamic>> rows =
                                messages.data ?? <Map<String, dynamic>>[];
                            if (rows.isEmpty) {
                              return _AccountEmptyView(
                                icon: Icons.forum_outlined,
                                title: context.tr('chat.emptyTitle'),
                                body: context.tr('chat.emptyBody'),
                              );
                            }
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_scrollController.hasClients) {
                                _scrollController.animateTo(
                                  _scrollController.position.maxScrollExtent,
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut,
                                );
                              }
                            });
                            return ListView.builder(
                              controller: _scrollController,
                              padding: KodimaliSpacing.screenPadding,
                              itemCount: rows.length,
                              itemBuilder: (BuildContext context, int index) {
                                final Map<String, dynamic> message =
                                    rows[index];
                                final bool mine =
                                    message['sender_id'] ==
                                    widget.repository.currentUser?.id;
                                return _MessageBubble(
                                  message: message,
                                  mine: mine,
                                );
                              },
                            );
                          },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              minLines: 1,
                              maxLines: 4,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: context.tr('chat.hint'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _sending
                                ? null
                                : () => _send(conversationId),
                            icon: _sending
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});

  final Map<String, dynamic> message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? colors.primaryContainer : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomRight: mine ? const Radius.circular(4) : null,
            bottomLeft: mine ? null : const Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(message['body']?.toString() ?? ''),
            const SizedBox(height: 3),
            Text(
              _formatCustomerDate(context, message['created_at']),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerViewingAppointmentScreen extends StatefulWidget {
  const CustomerViewingAppointmentScreen({
    super.key,
    required this.bookingRequestId,
    required this.repository,
  });

  final String bookingRequestId;
  final CustomerAccountRepository repository;

  @override
  State<CustomerViewingAppointmentScreen> createState() =>
      _CustomerViewingAppointmentScreenState();
}

class _CustomerViewingAppointmentScreenState
    extends State<CustomerViewingAppointmentScreen> {
  final TextEditingController _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 10, minute: 0);
  bool _submitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
    );
    if (date != null && mounted) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (time != null && mounted) {
      setState(() => _selectedTime = time);
    }
  }

  Future<void> _submit() async {
    final DateTime start = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    if (!start.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('viewing.futureError'))),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.repository.proposeViewingAppointment(
        bookingRequestId: widget.bookingRequestId,
        scheduledStartAt: start,
        scheduledEndAt: start.add(const Duration(hours: 1)),
        locationNote: _noteController.text,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_accountError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('viewing.propose'))),
      body: ListView(
        padding: KodimaliSpacing.screenPadding,
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(KodimaliSpacing.md),
              child: Text(context.tr('viewing.explainer')),
            ),
          ),
          const SizedBox(height: KodimaliSpacing.md),
          OutlinedButton.icon(
            onPressed: _submitting ? null : _pickDate,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(localizations.formatMediumDate(_selectedDate)),
          ),
          const SizedBox(height: KodimaliSpacing.sm),
          OutlinedButton.icon(
            onPressed: _submitting ? null : _pickTime,
            icon: const Icon(Icons.schedule_outlined),
            label: Text(localizations.formatTimeOfDay(_selectedTime)),
          ),
          const SizedBox(height: KodimaliSpacing.md),
          TextField(
            controller: _noteController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: context.tr('viewing.note'),
              helperText: context.tr('viewing.noteHelp'),
            ),
          ),
          const SizedBox(height: KodimaliSpacing.lg),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: const Icon(Icons.send_rounded),
            label: Text(
              _submitting
                  ? context.tr('request.submitting')
                  : context.tr('viewing.send'),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerReviewScreen extends StatefulWidget {
  const CustomerReviewScreen({
    super.key,
    required this.bookingRequestId,
    required this.repository,
    this.existingReview,
  });

  final String bookingRequestId;
  final CustomerAccountRepository repository;
  final Map<String, dynamic>? existingReview;

  @override
  State<CustomerReviewScreen> createState() => _CustomerReviewScreenState();
}

class _CustomerReviewScreenState extends State<CustomerReviewScreen> {
  final TextEditingController _commentController = TextEditingController();
  int _rating = 0;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _rating =
        int.tryParse(widget.existingReview?['rating']?.toString() ?? '') ?? 0;
    _commentController.text =
        widget.existingReview?['comment']?.toString() ?? '';
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('review.ratingError'))));
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.repository.submitReview(
        bookingRequestId: widget.bookingRequestId,
        rating: _rating,
        comment: _commentController.text,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_accountError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('review.title'))),
      body: ListView(
        padding: KodimaliSpacing.screenPadding,
        children: <Widget>[
          Text(
            context.tr('review.prompt'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: KodimaliSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(5, (int index) {
              final int value = index + 1;
              return IconButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() => _rating = value),
                iconSize: 40,
                tooltip: '$value / 5',
                icon: Icon(
                  value <= _rating
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: KodimaliColors.warning,
                ),
              );
            }),
          ),
          const SizedBox(height: KodimaliSpacing.md),
          TextField(
            controller: _commentController,
            maxLines: 5,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: context.tr('review.comment'),
            ),
          ),
          const SizedBox(height: KodimaliSpacing.md),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: const Icon(Icons.rate_review_outlined),
            label: Text(
              _submitting
                  ? context.tr('request.submitting')
                  : context.tr('review.submit'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountErrorView extends StatelessWidget {
  const _AccountErrorView({required this.message, required this.onRetry});

  final String message;
  final FutureOr<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return _AccountEmptyView(
      icon: Icons.cloud_off_outlined,
      title: context.tr('category.error'),
      body: message,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(context.tr('location.retry')),
      ),
    );
  }
}

class _AccountEmptyView extends StatelessWidget {
  const _AccountEmptyView({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: KodimaliSpacing.md),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KodimaliSpacing.xs),
            Text(body, textAlign: TextAlign.center),
            if (action != null) ...<Widget>[
              const SizedBox(height: KodimaliSpacing.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountLanguageButton extends StatelessWidget {
  const _AccountLanguageButton();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: context.tr('hero.language'),
      icon: const Icon(Icons.language_rounded),
      initialValue: context.languageCode,
      onSelected: context.setLanguageCode,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'sw', child: Text(context.tr('lang.sw'))),
        PopupMenuItem<String>(value: 'en', child: Text(context.tr('lang.en'))),
      ],
    );
  }
}

class _CustomerRequestDetailData {
  const _CustomerRequestDetailData({
    required this.request,
    required this.history,
    required this.appointments,
    required this.review,
  });

  final Map<String, dynamic> request;
  final List<Map<String, dynamic>> history;
  final List<Map<String, dynamic>> appointments;
  final Map<String, dynamic>? review;
}
