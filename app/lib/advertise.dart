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

  String _type = 'banner';           // banner | video
  String _pack = 'Starter — 5,000 views · ₹300';
  bool _custom = false;
  final _amountCtrl = TextEditingController(text: '300');
  final _viewsCtrl = TextEditingController(text: '5000');

  static const int kCpmBanner = 60;
  static const int kCpmVideo = 200;
  static const int kMinTopup = 200;

  int get _cpm => _type == 'video' ? kCpmVideo : kCpmBanner;

  static const Map<String, Map<String, int>> _packs = {
    'banner': {
      'Starter — 5,000 views · ₹300': 300,
      'Growth — 20,000 views · ₹1,000': 1000,
      'Pro — 50,000 views · ₹2,000': 2000,
    },
    'video': {
      'Starter — 2,000 views · ₹400': 400,
      'Growth — 10,000 views · ₹1,700': 1700,
    },
  };

  int get _price {
    if (!_custom) return _packs[_type]?[_pack] ?? 300;
    return int.tryParse(_amountCtrl.text.trim()) ?? 0;
  }

  int get _views {
    if (!_custom) {
      final label = _pack;
      final digits = RegExp(r'[0-9,]+').firstMatch(label)?.group(0) ?? '';
      return int.tryParse(digits.replaceAll(',', '')) ?? 0;
    }
    return int.tryParse(_viewsCtrl.text.trim()) ?? 0;
  }

  void _syncFromAmount() {
    final a = int.tryParse(_amountCtrl.text.trim()) ?? 0;
    final v = (a * 1000 / _cpm).round();
    _viewsCtrl.text = v.toString();
    setState(() {});
  }

  void _syncFromViews() {
    final v = int.tryParse(_viewsCtrl.text.trim()) ?? 0;
    final a = (v * _cpm / 1000).round();
    _amountCtrl.text = a.toString();
    setState(() {});
  }

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
    if (_price < kMinTopup) return _say('Minimum ₹$kMinTopup ka pack hai.');
    if (_views <= 0) return _say('Views calculate nahi hue — amount ya views check karo.');

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
              'plan': '${_type == 'video' ? 'Video' : 'Banner'} · ${_views} views',
              'amount': _price,
              'views': _views,
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
          const Text('Ad type', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kMuted)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _type = 'banner';
                    _pack = _packs['banner']!.keys.first;
                  }),
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _type == 'banner' ? kBrand.withOpacity(0.18) : kSurface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _type == 'banner' ? kBrand : kLine),
                    ),
                    child: Text('Banner · ₹$kCpmBanner /1000',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _type == 'banner' ? kBrand : kText)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _type = 'video';
                    _pack = _packs['video']!.keys.first;
                  }),
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _type == 'video' ? kBrand.withOpacity(0.18) : kSurface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _type == 'video' ? kBrand : kLine),
                    ),
                    child: Text('Video · ₹$kCpmVideo /1000',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _type == 'video' ? kBrand : kText)),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Pack', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kMuted)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _custom = !_custom),
                child: Text(_custom ? 'Fixed packs' : 'Custom (₹ / views)',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kBrand)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (!_custom)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: kSurface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kLine),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _packs[_type]!.containsKey(_pack) ? _pack : _packs[_type]!.keys.first,
                  isExpanded: true,
                  dropdownColor: kSurface,
                  items: [
                    for (final k in _packs[_type]!.keys)
                      DropdownMenuItem(value: k, child: Text(k, style: const TextStyle(fontSize: 13))),
                  ],
                  onChanged: (v) => setState(() => _pack = v ?? _pack),
                ),
              ),
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amountCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13),
                        onChanged: (_) => _syncFromAmount(),
                        decoration: const InputDecoration(labelText: '₹ amount', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _viewsCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13),
                        onChanged: (_) => _syncFromViews(),
                        decoration: const InputDecoration(labelText: 'Views', isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '₹${_price} = ${_views} views  (₹$_cpm per 1000 views)',
                    style: const TextStyle(fontSize: 11.5, color: kBrand, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 4),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Minimum ₹200 · 60 din validity',
                      style: TextStyle(fontSize: 10.5, color: kMuted)),
                ),
              ],
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
                Text('₹$_price pay karo  ·  ${_views} views',
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
