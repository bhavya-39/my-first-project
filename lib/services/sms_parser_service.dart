import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/expense_model.dart';

// ── Confidence thresholds ─────────────────────────────────────────────────────
const int _kAutoAddThreshold = 70;
// _kReviewThreshold is intentionally removed; rejection threshold is now 30.

// ── Trusted sender whitelist ──────────────────────────────────────────────────
const _trustedSenders = {
  // Major Private Banks
  'HDFCBK', 'HDFCBANK', 'HDFC', 'ICICIB', 'ICICIBANK', 'ICICI',
  'AXISBK', 'AXISBANK', 'AXIS', 'KOTAKBK', 'KOTAK', 'YESBNK', 'YESBANK',
  'INDBNK', 'INDIBNK', 'IDFC', 'IDFCBK', 'IDFCFB', 'FEDERAL', 'SOUTHBANK',
  'RBLBNK', 'RBLBANK', 'DCBBNK', 'DCBBANK', 'SARASWAT', 'KARNATAKA',
  'BANDHAN', 'UJJIVAN', 'EQUITAS', 'FINCARE', 'SURYODAY', 'ESAFBNK',
  // Major Public Banks
  'SBIBNK', 'SBIINB', 'SBI', 'SBIPSG', 'SBIMSG', 'BOBBNK', 'PNBSMS',
  'CANARA', 'CANBK', 'UNION', 'CBI', 'IOB', 'BOI', 'INDIAN', 'UCO', 'IDBI',
  'MAHABNK', 'MAHBNK', 'SYNDICB', 'VIJAYA', 'DENABNK', 'ANDBNK',
  'ALLABNK', 'CORPBNK', 'OBOBC', 'PSBSMS',
  // Foreign/Other Banks
  'CITI', 'CITIBNK', 'STANCH', 'SCBNK', 'HSBC', 'DBS', 'KVB', 'DBSBNK',
  'BARODA', 'BAROBNK',
  // UPI / FinTech Apps
  'PAYTM', 'PYTMMB', 'PAYTMSMS', 'GPAY', 'GOOGLEPAY', 'PHONEPE', 'PHONPE',
  'BHARATPE', 'BHIMAPP', 'BHIMUPI', 'AMAZONPAY', 'AMZNPAY', 'CRED',
  'FAMPAY', 'SLICE', 'POSTPE', 'MOBIKWIK', 'FREECHARGE', 'LAZYP', 'LAZYPAY',
  'JUPITER', 'FISDOM', 'NIYO', 'NIYOBNK',
};

// ── Debit-indicating keywords ─────────────────────────────────────────────────
final _debitWords = RegExp(
  r'\b(debit(?:ed)?|spent|paid|payment(?:\s+of)?|purchase|charged|withdrawn|deducted|sent|'
  r'transferred to|pos|mandate|auto.?pay|emi|standing instruction|si executed)\b',
  caseSensitive: false,
);

// ── Rejection keywords — any match immediately discards the message ───────────
// NOTE: Keep this list NARROW — only block clearly non-transactional messages.
// Do NOT add words like 'interest', 'emi', 'bill' as many real debit SMS contain them.
final _rejectWords = RegExp(
  r'\b(refund(?:ed)?|revers(?:ed|al)|cashback|failed|declined|blocked|insufficient funds|'
  r'otp|one.?time password|never share your|a\/c created|account created|'
  r'nominee|fd book|fd open|kyc|login alert|lucky draw|pre-approv)\b',
  caseSensitive: false,
);

// ── Purely informational / promotional ───────────────────────────────────────
final _promoWords = RegExp(
  r'\b(offer|discount|reward|earn|win|congratul|lucky draw|click|http|www\.|loan offer|pre-approv)\b',
  caseSensitive: false,
);

// ── Amount patterns ──────────────────────────────────────────────────────────
final _amountPatterns = [
  RegExp(r'(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d{0,2})', caseSensitive: false),
  RegExp(r'([\d,]+\.?\d{0,2})\s*(?:Rs\.?|INR|₹)', caseSensitive: false),
];

// ── Merchant / payee extraction ───────────────────────────────────────────────
final _merchantPatterns = [
  RegExp(
      r'(?:to|at|for|towards)\s+([A-Za-z0-9&@._\-\s]{2,40}?)(?:\s+(?:on|via|at|using|UPI|Ref|VPA|A\/C|ref\.)|\.|,|$)',
      caseSensitive: false),
  RegExp(r'VPA\s+([A-Za-z0-9@._\-]{4,40})', caseSensitive: false),
  RegExp(r'Merchant\s*[:\-]\s*([A-Za-z0-9&\s._\-]{2,40})',
      caseSensitive: false),
];

// ── Merchant noise words to strip from extracted merchant name ────────────────
final _merchantNoise = RegExp(
  r'\s*(UPI|IMPS|NEFT|RTGS|Ref|VPA|A\/C|AC|on\s+\d|at\s+\d|using|via|the|your|from|to|is)\s*$',
  caseSensitive: false,
);

// ── Category keyword mapping ──────────────────────────────────────────────────
const _categoryKeywords = <String, List<String>>{
  'Food & Groceries': [
    'zomato', 'swiggy', 'dominos', 'kfc', 'mcdonalds', 'subway', 'pizza', 'burger king',
    'starbucks', 'cafe', 'restaurant', 'food', 'eat', 'biryani', 'haldiram', 'bikanervala',
    'blinkit', 'zepto', 'dunzo', 'groceries', 'bigbasket', 'grofer', 'instamart', 'bbnow',
    'dmart', 'reliance fresh', 'nature', 'sweet', 'bakery', 'licious', 'freshtohome',
  ],
  'Shopping': [
    'amazon', 'flipkart', 'myntra', 'meesho', 'ajio', 'nykaa', 'firstcry',
    'snapdeal', 'tatacliq', 'shopping', 'store', 'mart', 'mall', 'supermarket',
    'decathlon', 'zara', 'h&m', 'max', 'pantaloons', 'shoppers stop', 'croma',
    'reliance digital', 'lenskart', 'titan', 'apparel', 'clothing', 'footwear',
  ],
  'Transport': [
    'uber', 'ola', 'rapido', 'namma yatri', 'indrive', 'blu smart', 'irctc', 'train',
    'railway', 'bus', 'flight', 'makemytrip', 'yatra', 'easemytrip', 'cleartrip',
    'redbus', 'ixigo', 'metro', 'toll', 'fastag', 'park+', 'parking', 'petrol',
    'diesel', 'cng', 'fuel', 'hpcl', 'iocl', 'bpcl', 'indian oil', 'shell',
  ],
  'Entertainment': [
    'netflix', 'hotstar', 'spotify', 'prime', 'sony', 'zee', 'bookmyshow',
    'inox', 'pvr', 'cinepolis', 'youtube', 'apple', 'game', 'play store',
    'steam', 'epic games', 'playstation', 'xbox', 'nintendo', 'paytm movies',
  ],
  'Utilities': [
    'electricity', 'water', 'gas', 'broadband', 'jio', 'airtel', 'vi ', 'vodafone',
    'bsnl', 'tata sky', 'tata play', 'dth', 'recharge', 'postpaid', 'prepaid', 'internet',
    'bescom', 'msedcl', 'tata power', 'adani', 'bses', 'uppcl', 'tneb', 'torrent',
    'act fibernet', 'hathway', 'excitel', 'wifi', 'bill',
  ],
  'Health': [
    'hospital', 'clinic', 'pharmacy', 'medical', 'doctor', 'lab', 'test',
    'medicine', 'apollo', 'fortis', 'max healthcare', 'netmeds', '1mg', 'pharmeasy',
    'practo', 'srl diagnostics', 'dr lal', 'dental', 'eye care', 'spectacles',
    'fitness', 'cult fit', 'gym', 'health',
  ],
  'Housing': [
    'rent', 'deposit', 'maintenance', 'urban company', 'urban clap', 'nobroker',
    'magicbricks', 'home centre', 'pepperfry', 'ikea', 'furniture', 'plumber',
  ],
  'Education': [
    'school', 'college', 'university', 'byju', 'unacademy', 'vedantu', 'physics wallah',
    'udemy', 'coursera', 'upgrad', 'fees', 'tuition', 'books', 'stationery',
  ],
  'Investment': [
    'zerodha', 'groww', 'upstox', 'angel one', 'indmoney', 'mutual fund', 'sip',
    'lic', 'insurance', 'hdfc life', 'sbi life', 'policybazaar', 'investment',
  ],
  'Transfers': [
    'transfer', 'send money', 'neft', 'imps', 'rtgs', 'bank transfer', 'upi',
    'wallet load', 'to account',
  ],
};

/// Result of parsing a single SMS message.
class ParsedExpense {
  final double amount;
  final String merchant;
  final String category;
  final String? bank;
  final DateTime timestamp;
  final int confidence; // 0–100
  final bool needsReview;
  final String hash;

  const ParsedExpense({
    required this.amount,
    required this.merchant,
    required this.category,
    this.bank,
    required this.timestamp,
    required this.confidence,
    required this.needsReview,
    required this.hash,
  });

  Expense toExpense() => Expense(
        hash: hash,
        amount: amount,
        merchant: merchant,
        category: category,
        bank: bank,
        date: timestamp,
        note: 'Auto-imported from SMS',
        needsReview: needsReview,
        confidence: confidence,
      );
}

/// Rule-based UPI/bank SMS parser with confidence scoring.
///
/// Scoring:
///   +40  amount extracted
///   +30  debit keyword present
///   +20  trusted sender header
///   +10  merchant extracted
/// ─────────────────────────────
///  ≥70  auto-add
///  40–69 mark as "Needs Review"
///  <40  reject (return null)
class SmsParserService {
  const SmsParserService();

  /// Returns null if the message is not a valid UPI debit transaction.
  ParsedExpense? parse(String body, String? sender, DateTime timestamp) {
    // ── Step 1: Rejection filters ──────────────────────────────────────────
    if (_rejectWords.hasMatch(body)) return null;
    if (_promoWords.hasMatch(body)) return null;
    if (!_debitWords.hasMatch(body)) return null; // must have debit word

    // ── Step 2: Context-aware amount extraction ────────────────────────────
    double? bestAmount;
    int minDistanceToDebit = 999999;
    
    // Find all occurrences of amount patterns
    final matches = <RegExpMatch>[];
    for (final pattern in _amountPatterns) {
      matches.addAll(pattern.allMatches(body));
    }
    
    final debitMatches = _debitWords.allMatches(body).toList();
    if (debitMatches.isEmpty) return null; // Must have debit words

    // Balance keywords to ignore
    final balanceWords = RegExp(r'\b(bal(ance)?|avl|available|limit)\b', caseSensitive: false);
    final balanceMatches = balanceWords.allMatches(body).toList();
    
    for (final m in matches) {
      final raw = m.group(1)!.replaceAll(',', '');
      final amountCandidate = double.tryParse(raw);
      // Ignore invalid, zero, or excessively large amounts > ₹10,00,000
      if (amountCandidate == null || amountCandidate <= 0 || amountCandidate > 1000000) continue;
      
      final amountIndex = m.start;
      
      // Check if this amount is IMMEDIATELY next to a balance/limit keyword.
      // Use a wider window (60 chars) but only skip if the balance keyword appears
      // AFTER the amount (i.e., "debited Rs.500 Bal: Rs.2000" – skip the 2000 not the 500).
      bool nearBalance = false;
      for (final bm in balanceMatches) {
        final dist = bm.start - amountIndex; // positive = balance is after amount
        // Ignore if balance keyword is within 5–80 chars AFTER the amount
        if (dist > 5 && dist < 80) {
          nearBalance = true;
          break;
        }
      }
      if (nearBalance) continue; // Ignore balance amounts
      
      // Calculate distance to nearest debit keyword
      int distanceToDebit = 999999;
      for (final dm in debitMatches) {
        final dist = (dm.start - amountIndex).abs();
        if (dist < distanceToDebit) {
          distanceToDebit = dist;
        }
      }
      
      // Select the amount closest to a debit keyword
      if (distanceToDebit < minDistanceToDebit) {
        minDistanceToDebit = distanceToDebit;
        bestAmount = amountCandidate;
      }
    }
    
    if (bestAmount == null) return null; // No valid amount found
    double amount = bestAmount;

    // ── Step 3: Confidence scoring ────────────────────────────────────────
    int score = 45; // found amount (+45)
    score += 25; // passed debit word check (+25)

    final normalizedSender = sender?.toUpperCase().replaceAll('-', '') ?? '';
    final isTrusted = _trustedSenders.any(
        (s) => normalizedSender.contains(s));
    if (isTrusted) score += 20;

    // ── Step 4: Merchant extraction ───────────────────────────────────────
    String merchant = 'Unknown';
    for (final pattern in _merchantPatterns) {
      final m = pattern.firstMatch(body);
      if (m != null) {
        final raw = m.group(1)?.trim() ?? '';
        final cleaned = raw.replaceAll(_merchantNoise, '').trim();
        if (cleaned.length >= 2 && cleaned.length <= 50) {
          merchant = _toTitleCase(cleaned);
          score += 10;
          break;
        }
      }
    }

    // ── Step 5: Below reject threshold? ──────────────────────────────────
    // Lowered threshold: any message with an amount + debit word scores ≥70
    // so practically only completely unscored messages are rejected here.
    if (score < 30) return null;

    // ── Step 6: Category + bank ───────────────────────────────────────────
    final category = _inferCategory(body, merchant);
    final bank = _inferBank(normalizedSender);

    // ── Step 7: Deduplication hash ────────────────────────────────────────
    // Hash on: merchant + rounded-amount + minute-level timestamp
    final minuteKey =
        '${timestamp.year}${timestamp.month}${timestamp.day}${timestamp.hour}${timestamp.minute}';
    final rawHash = '$merchant|${amount.toStringAsFixed(2)}|$minuteKey';
    final hash = md5.convert(utf8.encode(rawHash)).toString();

    return ParsedExpense(
      amount: amount,
      merchant: merchant,
      category: category,
      bank: bank,
      timestamp: timestamp,
      confidence: score.clamp(0, 100),
      needsReview: score < _kAutoAddThreshold,
      hash: hash,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _inferCategory(String body, String merchant) {
    final lower = '${body.toLowerCase()} ${merchant.toLowerCase()}';
    for (final entry in _categoryKeywords.entries) {
      if (entry.value.any(lower.contains)) return entry.key;
    }
    return 'Other';
  }

  String? _inferBank(String sender) {
    if (sender.contains('HDFC')) return 'HDFC Bank';
    if (sender.contains('ICICI')) return 'ICICI Bank';
    if (sender.contains('SBI')) return 'SBI';
    if (sender.contains('AXIS')) return 'Axis Bank';
    if (sender.contains('KOTAK')) return 'Kotak Bank';
    if (sender.contains('YES')) return 'Yes Bank';
    if (sender.contains('PAYTM') || sender.contains('PYTM')) return 'Paytm';
    if (sender.contains('GPAY') || sender.contains('GOOGLE')) return 'Google Pay';
    if (sender.contains('PHONE') || sender.contains('PHONPE')) return 'PhonePe';
    if (sender.contains('AMAZON') || sender.contains('AMZN')) return 'Amazon Pay';
    return null;
  }

  String _toTitleCase(String s) {
    return s
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }
}
