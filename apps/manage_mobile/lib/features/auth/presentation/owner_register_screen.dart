import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/manage_localization.dart';

class OwnerRegisterScreen extends StatefulWidget {
  const OwnerRegisterScreen({super.key});
  @override
  State<OwnerRegisterScreen> createState() => _OwnerRegisterScreenState();
}

class _OwnerRegisterScreenState extends State<OwnerRegisterScreen> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final authority = TextEditingController();
  String ownerType = 'venue_owner';
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    email.dispose();
    password.dispose();
    authority.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sw = context.isSwahili;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          sw ? 'Usajili wa mmiliki au meneja' : 'Owner or manager registration',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            sw ? 'Sajili biashara yako' : 'Register your business',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            sw
                ? 'Mmiliki wa ukumbi achague “Mmiliki wa venue”. Meneja asiye mmiliki achague “Meneja mwenye ruhusa”. Admin atathibitisha mamlaka kabla ya kufungua workspace.'
                : 'Hall owners choose “Venue owner”. A manager acting for an owner chooses “Authorized manager”. Admin verifies authority before workspace access.',
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: ownerType,
            decoration: InputDecoration(
              labelText: sw ? 'Aina ya akaunti' : 'Account type',
            ),
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem(
                value: 'venue_owner',
                child: Text(
                  sw ? 'Mmiliki wa hall au venue' : 'Hall or venue owner',
                ),
              ),
              DropdownMenuItem(
                value: 'authorized_manager',
                child: Text(sw ? 'Meneja mwenye ruhusa' : 'Authorized manager'),
              ),
              DropdownMenuItem(
                value: 'equipment_owner',
                child: Text(sw ? 'Mmiliki wa vifaa' : 'Equipment owner'),
              ),
              DropdownMenuItem(
                value: 'vehicle_owner',
                child: Text(sw ? 'Mmiliki wa gari' : 'Vehicle owner'),
              ),
              DropdownMenuItem(
                value: 'individual',
                child: Text(sw ? 'Mmiliki binafsi' : 'Individual owner'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => ownerType = value);
            },
          ),
          TextField(
            controller: name,
            decoration: InputDecoration(
              labelText: sw ? 'Jina la kisheria' : 'Legal name',
            ),
          ),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: sw ? 'Namba ya simu' : 'Phone number',
            ),
          ),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          TextField(
            controller: password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: sw ? 'Nenosiri' : 'Password',
            ),
          ),
          TextField(
            controller: authority,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: sw
                  ? 'Eleza umiliki au ruhusa yako ya kusimamia'
                  : 'Describe your ownership or management authority',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : _submit,
            child: Text(
              busy
                  ? (sw ? 'Inatuma…' : 'Submitting…')
                  : (sw ? 'Tuma kwa uhakiki' : 'Submit for verification'),
            ),
          ),
          TextButton(
            onPressed: () => context.go('/login'),
            child: Text(
              sw ? 'Tayari una akaunti? Ingia' : 'Already registered? Sign in',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (name.text.trim().isEmpty ||
        phone.text.trim().isEmpty ||
        email.text.trim().isEmpty ||
        password.text.length < 6 ||
        authority.text.trim().isEmpty) {
      return;
    }
    setState(() => busy = true);
    try {
      await Supabase.instance.client.auth.signUp(
        email: email.text.trim().toLowerCase(),
        password: password.text,
        data: <String, dynamic>{
          'full_name': name.text.trim(),
          'phone_number': phone.text.trim(),
          'preferred_language': 'sw',
          'register_as_owner': true,
          'registration_source': 'owner_self_register_manage_app',
          'owner_type': ownerType,
          'authorization_summary': authority.text.trim(),
        },
      );
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.isSwahili
                  ? 'Ombi limepokelewa. Thibitisha email kisha subiri uhakiki wa admin.'
                  : 'Application received. Confirm email, then wait for admin verification.',
            ),
          ),
        );
        context.go('/login');
      }
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }
}
