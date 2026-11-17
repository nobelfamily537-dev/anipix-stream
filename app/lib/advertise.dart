import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'ui.dart';

const String kUpiId = 'lavkushkumar3258@naviaxis';
const String kAdvertiseTelegram = 'https://t.me/lovelyanime_admin';

String upiLink({String note = 'AniPix'}) =>
    'upi://pay?pa=$kUpiId&pn=AniPix%20Stream&cu=INR&tn=$note';

/// Public "advertise with us" screen: pay by UPI, then submit the request.
class AdvertiseScreen extends StatefulWidget {
  const AdvertiseScreen({super.key});

  @override
  State<AdvertiseScreen> createState() => _AdvertiseScreenState();
}

class _AdvertiseScreenState extends State<AdvertiseScreen> {
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _link = TextEditingController();
  final _txn = TextEditingController();
  final _note = TextEditingController();

  String _plan = 'Banner — ₹800 / month';
  int _amount = 800;
  bool _busy = false;
  String? _msg;
  bool _ok = false;

  static const _plans = <String, int>{
    'Banner — ₹800 / month': 800,
    'Banner x2 — ₹1,200 / month': 1200,
    'Video ad — ₹2,000 / month': 2000,
    'Full package — ₹3,000 / month': 3000,
    'Telegram post — ₹300': 300,
  };

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _link.dispose();
    _txn.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return _say('Apna naam / business ka naam likho.');
    if (_contact.text.trim().isEmpty) return _say('Contact (phone ya Telegram) likho.');
    if (_txn.text.trim().isEmpty) return _say('Payment ke baad transaction ID daalo.');

    setState(() => _busy = true);
    try {
      final res = await http
          .post(
            Uri.parse('$kBaseUrl/api/ads'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'action': 'request',
              'name': _name.text.trim(),
              'contact': _contact.text.trim(),
              'link': _link.text.trim(),
              'plan': _plan,
              'amount': _amount,
              'txnId': _txn.text.trim(),
              'note': _note.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 25));
      final j = jsonDecode(res.body);
      final ok = res.statusCode == 200 && j is Map && j['ok'] == true;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = ok;
        _msg = ok
            ? 'Request bhej di ✅ Admin verify karega (24 ghante). Screenshot @lovelyanime_admin par bhej do.'
            : 'Kuch galat hua. Dobara try karo.';
      });
      if (ok) {
        _name.clear();
        _contact.clear();
        _link.clear();
        _txn.clear();
        _note.clear();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = false;
        _msg = 'Network error. Dobara try karo.';
      });
    }
  }

  void _say(String m) => setState(() {
        _msg = m;
        _ok = false;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advertise with us')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          const Text('Apne product ko AniPix users tak pahuchao',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            'Banner app ke home par dikhta hai. Video ad episode se pehle. '
            'Har ad admin approve karta hai, phir live hota hai.',
            style: TextStyle(fontSize: 12, color: kMuted, height: 1.5),
          ),

          const SizedBox(height: 18),
          const Text('Plan chuno', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kMuted)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: kSurface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kLine),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _plan,
                isExpanded: true,
                dropdownColor: kSurface,
                items: [
                  for (final e in _plans.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.key, style: const TextStyle(fontSize: 13))),
                ],
                onChanged: (v) => setState(() {
                  _plan = v ?? _plan;
                  _amount = _plans[_plan] ?? 800;
                }),
              ),
            ),
          ),

          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kSurface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kLine),
            ),
            child: Column(
              children: [
                Text('₹$_amount pay karo',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: QrImageView(
                    data: upiLink(note: 'AniPix ad'),
                    size: 170,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SelectableText(kUpiId,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: kBrand)),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16, color: kMuted),
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: kUpiId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('UPI ID copied'), duration: Duration(seconds: 2)),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: kBrand.withOpacity(0.6)),
                    foregroundColor: kBrand,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('Open UPI app', style: TextStyle(fontSize: 12)),
                  onPressed: () => launchUrl(Uri.parse(upiLink(note: 'AniPix ad')),
                      mode: LaunchMode.externalApplication),
                ),
                const SizedBox(height: 6),
                const Text('Payment ke baad transaction ID neeche daalo',
                    style: TextStyle(fontSize: 10.5, color: kMuted)),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _tf('Your name / business', _name, hint: 'Anime Merch Store'),
          _tf('Contact (phone / Telegram)', _contact, hint: '@username or 98xxxxxx'),
          _tf('Website or link (optional)', _link, hint: 'https://…'),
          _tf('Transaction ID / UTR', _txn, hint: '12 digit UTR'),
          _tf('Note (optional)', _note),

          const SizedBox(height: 6),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrand,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Send request', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),

          if (_msg != null) ...[
            const SizedBox(height: 12),
            Text(_msg!,
                style: TextStyle(fontSize: 12, color: _ok ? kBrand : const Color(0xFFFF9D9D), height: 1.4)),
          ],

          const SizedBox(height: 22),
          Center(
            child: TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(kAdvertiseTelegram),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.telegram, size: 17, color: kBrand),
              label: const Text('Advertiser support — @lovelyanime_admin',
                  style: TextStyle(fontSize: 12, color: kBrand)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tf(String label, TextEditingController c, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
      ),
    );
  }
}
