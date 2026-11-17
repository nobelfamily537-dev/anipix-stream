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

/// Public "advertise with us" flow:
/// details → price → pay (QR) → transaction id → send → wait for admin.
class AdvertiseScreen extends StatefulWidget {
  const AdvertiseScreen({super.key});

  @override
  State<AdvertiseScreen> createState() => _AdvertiseScreenState();
}

class _AdvertiseScreenState extends State<AdvertiseScreen> {
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _link = TextEditingController();
  final _note = TextEditingController();
  final _txn = TextEditingController();
  final _amountCtrl = TextEditingController(text: '300');
  final _viewsCtrl = TextEditingController(text: '5000');

  String _type = 'banner';          // banner | video
  int _packIndex = 0;               // 0 starter, 1 growth, 2 pro, 3 custom
  bool _busy = false;
  String? _msg;
  bool _ok = false;
  bool _sent = false;

  static const int kCpmBanner = 60;
  static const int kCpmVideo = 200;
  static const int kMinTopup = 200;

  int get _cpm => _type == 'video' ? kCpmVideo : kCpmBanner;

  static const List<List<String>> _packLabels = [
    ['Starter', '5,000 views'],
    ['Growth', '20,000 views'],
    ['Pro', '50,000 views'],
    ['Custom', 'apne hisaab se'],
  ];

  int get _views {
    if (_packIndex == 0) return 5000;
    if (_packIndex == 1) return 20000;
    if (_packIndex == 2) return 50000;
    return int.tryParse(_viewsCtrl.text.trim()) ?? 0;
  }

  int get _price {
    if (_packIndex == 0) return _type == 'video' ? 400 : 300;
    if (_packIndex == 1) return _type == 'video' ? 1700 : 1000;
    if (_packIndex == 2) return _type == 'video' ? 3400 : 2000;
    return int.tryParse(_amountCtrl.text.trim()) ?? 0;
  }

  void _syncFromAmount() {
    final a = int.tryParse(_amountCtrl.text.trim()) ?? 0;
    _viewsCtrl.text = (a * 1000 / _cpm).round().toString();
    setState(() {});
  }

  void _syncFromViews() {
    final v = int.tryParse(_viewsCtrl.text.trim()) ?? 0;
    _amountCtrl.text = (v * _cpm / 1000).round().toString();
    setState(() {});
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _link.dispose();
    _note.dispose();
    _txn.dispose();
    _amountCtrl.dispose();
    _viewsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return _say('Naam / business ka naam likho.');
    if (_contact.text.trim().isEmpty) return _say('Contact (phone ya Telegram) likho.');
    if (_txn.text.trim().isEmpty) return _say('Payment ke baad transaction ID / UTR daalo.');
    if (_price < kMinTopup) return _say('Minimum ₹$kMinTopup ka pack hai.');

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
              'plan': '${_type == 'video' ? 'Video' : 'Banner'} · $_views views',
              'amount': _price,
              'views': _views,
              'type': _type,
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
        _sent = ok;
        _msg = ok ? null : 'Kuch galat hua. Dobara try karo.';
      });
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
    if (_sent) return _successScreen();

    return Scaffold(
      appBar: AppBar(title: const Text('Advertise with us')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          const Text('Apne product ko AniPix users tak pahuchao',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            'Banner app ke home par dikhta hai, video ad episode se pehle. '
            'Admin approve karne ke baad ad live hota hai.',
            style: TextStyle(fontSize: 12, color: kMuted, height: 1.5),
          ),

          /* ---------- 1. details ---------- */
          const SizedBox(height: 20),
          _step('1', 'Apni details bharo'),
          const SizedBox(height: 8),
          _tf('Your name / business', _name, hint: 'Anime Merch Store'),
          _tf('Contact (phone / Telegram)', _contact, hint: '@username or 98xxxxxx'),
          _tf('Website or link (optional)', _link, hint: 'https://…'),
          _tf('Note (optional)', _note),

          /* ---------- 2. type + pack ---------- */
          const SizedBox(height: 14),
          _step('2', 'Ad type aur views chuno'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _typeCard('banner', 'Banner', '₹$kCpmBanner /1000 views')),
              const SizedBox(width: 10),
              Expanded(child: _typeCard('video', 'Video', '₹$kCpmVideo /1000 views')),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _packLabels.length; i++) _packChip(i),
            ],
          ),
          if (_packIndex == 3) ...[
            const SizedBox(height: 12),
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
            Text('₹$_price = $_views views  ·  ₹$_cpm per 1000 views',
                style: const TextStyle(fontSize: 11.5, color: kBrand, fontWeight: FontWeight.w700)),
          ],

          /* ---------- 3. pay ---------- */
          const SizedBox(height: 20),
          _step('3', 'Payment karo'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kSurface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kLine),
            ),
            child: Column(
              children: [
                Text('₹$_price  ·  $_views views',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: QrImageView(data: upiLink(note: 'AniPix ad'), size: 165, backgroundColor: Colors.white),
                ),
                const SizedBox(height: 8),
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
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: kBrand.withOpacity(0.6)),
                    foregroundColor: kBrand,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('Open UPI app', style: TextStyle(fontSize: 12)),
                  onPressed: () =>
                      launchUrl(Uri.parse(upiLink(note: 'AniPix ad')), mode: LaunchMode.externalApplication),
                ),
              ],
            ),
          ),

          /* ---------- 4. txn ---------- */
          const SizedBox(height: 20),
          _step('4', 'Transaction ID daalo'),
          const SizedBox(height: 8),
          _tf('Transaction ID / UTR', _txn, hint: '12 digit UTR'),

          const SizedBox(height: 10),
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
                  : const Text('Submit request', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),

          if (_msg != null) ...[
            const SizedBox(height: 12),
            Text(_msg!,
                style: const TextStyle(fontSize: 12, color: Color(0xFFFF9D9D), height: 1.4)),
          ],

          const SizedBox(height: 18),
          Center(
            child: TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(kAdvertiseTelegram), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.telegram, size: 17, color: kBrand),
              label: const Text('Help — @lovelyanime_admin',
                  style: TextStyle(fontSize: 12, color: kBrand)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _successScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Request sent')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.check_circle, size: 64, color: kBrand),
          const SizedBox(height: 18),
          const Text('Request bhej di gayi ✅',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          const Text(
            'Ab admin ko Telegram par contact karo aur apna banner / video bhejo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: kMuted, height: 1.5),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kBrand.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBrand.withOpacity(0.45)),
            ),
            child: Column(
              children: [
                Text('₹$_price  ·  $_views views',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('48 ghante ke andar aapka ad app par dikhne lagega.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: kText, height: 1.45)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrand,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.telegram, size: 18),
              label: const Text('Contact admin on Telegram',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              onPressed: () =>
                  launchUrl(Uri.parse(kAdvertiseTelegram), mode: LaunchMode.externalApplication),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to app', style: TextStyle(fontSize: 12, color: kMuted)),
          ),
        ],
      ),
    );
  }

  Widget _step(String n, String title) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: kBrand, shape: BoxShape.circle),
          child: Text(n,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black)),
        ),
        const SizedBox(width: 9),
        Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _typeCard(String value, String label, String sub) {
    final on = _type == value;
    return GestureDetector(
      onTap: () => setState(() => _type = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? kBrand.withOpacity(0.18) : kSurface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? kBrand : kLine),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: on ? kBrand : kText)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(fontSize: 9.5, color: kMuted)),
          ],
        ),
      ),
    );
  }

  Widget _packChip(int i) {
    final on = _packIndex == i;
    return GestureDetector(
      onTap: () => setState(() => _packIndex = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: on ? kBrand.withOpacity(0.18) : kSurface2,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: on ? kBrand : kLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_packLabels[i][0],
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800, color: on ? kBrand : kText)),
            Text(_packLabels[i][1], style: const TextStyle(fontSize: 9.5, color: kMuted)),
          ],
        ),
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
