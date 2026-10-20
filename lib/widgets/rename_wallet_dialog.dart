// lib/widgets/rename_wallet_dialog.dart
//
// Reusable dialog for renaming a paired wallet.
// Reads / writes `wallet_name` on the `wallets` table row for the
// current user.  Also exposed as a standalone screen at /rename-wallet
// so it can be pushed from settings.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/app/theme.dart';

// ─── dialog ──────────────────────────────────────────────────────────────────

class RenameWalletDialog extends StatefulWidget {
  final String currentName;
  final String walletId;

  const RenameWalletDialog({
    super.key,
    required this.currentName,
    required this.walletId,
  });

  @override
  State<RenameWalletDialog> createState() => _RenameWalletDialogState();
}

class _RenameWalletDialogState extends State<RenameWalletDialog> {
  late final TextEditingController _ctrl;
  final _sb = Supabase.instance.client;
  bool _saving = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _err = 'Name cannot be empty');
      return;
    }
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      await _sb
          .from('wallets')
          .update({'wallet_name': name}).eq('id', widget.walletId);
      if (mounted) Navigator.of(context).pop(name);
    } catch (e) {
      setState(() {
        _saving = false;
        _err = 'Failed to save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? kSurface : kSurfaceLight;
    final border = dark ? kBorder : kBorderLight;
    final textP = dark ? kTextPrimary : kTextPrimaryLight;
    final textM = dark ? kTextMuted : kTextMutedLight;

    return AlertDialog(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Rename wallet',
          style: TextStyle(
              color: textP, fontSize: 18, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: 32,
            style: TextStyle(color: textP),
            decoration: InputDecoration(
              hintText: 'e.g. My EZlink Card',
              hintStyle: TextStyle(color: textM),
              counterStyle: TextStyle(color: textM, fontSize: 10),
              filled: true,
              fillColor: dark ? kBg : kBgLight,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: kAccent, width: 1.5)),
            ),
            onSubmitted: (_) => _save(),
          ),
          if (_err != null) ...[
            const SizedBox(height: 8),
            Text(_err!,
                style: TextStyle(
                    color: dark ? kError : kErrorLight, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: textM)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ─── screen wrapper (for /rename-wallet route) ────────────────────────────────

class RenameWalletScreen extends StatefulWidget {
  const RenameWalletScreen({super.key});

  @override
  State<RenameWalletScreen> createState() => _RenameWalletScreenState();
}

class _RenameWalletScreenState extends State<RenameWalletScreen> {
  final _sb = Supabase.instance.client;
  Map<String, dynamic>? _wallet;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _sb.auth.currentUser?.id;
    try {
      final res = await _sb
          .from('wallets')
          .select()
          .eq('user_id', uid!)
          .limit(1)
          .maybeSingle();
      setState(() {
        _wallet = res as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? kBg : kBgLight;
    final surface = dark ? kSurface : kSurfaceLight;
    final border = dark ? kBorder : kBorderLight;
    final textP = dark ? kTextPrimary : kTextPrimaryLight;
    final textS = dark ? kTextSecondary : kTextSecondaryLight;
    final textM = dark ? kTextMuted : kTextMutedLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: BackButton(color: textP),
        title: Text('Rename Wallet',
            style: TextStyle(
                color: textP, fontSize: 20, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: kAccent))
          : _wallet == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.credit_card_off_outlined,
                          color: textM, size: 48),
                      const SizedBox(height: 12),
                      Text('No wallet paired yet.',
                          style: TextStyle(color: textM)),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: border)),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                      colors: [kAccent, Color(0xFF9C88FF)]),
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.credit_card,
                                  color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _wallet!['wallet_name']?.toString() ??
                                        'My Wallet',
                                    style: TextStyle(
                                        color: textP,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16),
                                  ),
                                  Text(
                                    _wallet!['device_id']?.toString() ?? '—',
                                    style: TextStyle(
                                        color: textM, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.edit_outlined, color: kAccent),
                              onPressed: () async {
                                final newName =
                                    await showDialog<String>(
                                  context: context,
                                  builder: (_) => RenameWalletDialog(
                                    currentName:
                                        _wallet!['wallet_name']
                                                ?.toString() ??
                                            'My Wallet',
                                    walletId:
                                        _wallet!['id'].toString(),
                                  ),
                                );
                                if (newName != null) {
                                  setState(() => _wallet!['wallet_name'] =
                                      newName);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Wallet renamed to "$newName"'),
                                        backgroundColor: kSuccess,
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('Tip: Give your wallet a memorable name so you '
                          'can identify it quickly during pairing.',
                          style: TextStyle(color: textS, fontSize: 13)),
                    ],
                  ),
                ),
    );
  }
}