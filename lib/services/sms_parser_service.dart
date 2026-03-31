import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/expense_model.dart';

// ── Confidence thresholds ──────────────────────────────────────────────────────

// ── Trusted sender whitelist ──────────────────────────────────────────────────
const _trustedSenders = {
  // Literal Google Messages Sender Names
  'STATEBANK', 'OVERSEAS', 'BANKOF', 'PUNJABNATIONAL', 'UNIONBANK', 
  'CANARABANK', 'INDIANBANK', 'HDFCBANK', 'ICICIBANK', 'AXISBANK',
  // Major Private Banks
  'HDFCBK', 'HDFC',
  'ICICIB', 'ICICI',
  'AXISBK', 'AXIS',
  'KOTAKBK', 'KOTAK',
  'YESBNK', 'YESBANK',
  'INDBNK', 'INDIBNK',
  'IDFC', 'IDFCBK', 'IDFCFB',
  'FEDERAL', 'SOUTHBANK',
  'RBLBNK', 'RBLBANK',
  'DCBBNK', 'DCBBANK',
  'SARASWAT', 'KARNATAKA',
  'BANDHAN', 'UJJIVAN', 'EQUITAS', 'FINCARE', 'SURYODAY', 'ESAFBNK',
  // Major Public Banks
  'SBIBNK', 'SBIINB', 'SBI', 'SBIPSG', 'SBIMSG',
  'BOBBNK', 'BOBNK', 'BARBNK', 'BOBIOB',
  'PNBSMS', 'PNBBNK', 'PNB',
  'CANARA', 'CANBK', 'CANARABNK',
  'UNION', 'UNIONBNK', 'UBIBNK',
  'BOISMS', 'BOISBI', 'BOI', 'BOIBNK',
  'IOB', 'IOBSMS', 'IOBBNK', 'IOBBANK', 'IOBALERT',
  'CBI', 'CBIBNK',
  'UCO', 'UCOBNK',
  'IDBI', 'IDBIBNK',
  'MAHABNK', 'MAHBNK', 'MAHBOB',
  'SYNDICB', 'SYNDBNK',
  'VIJAYA', 'VIJBNK', 'VIJAYABNK',
  'DENABNK', 'DENA',
  'ANDBNK', 'ANDHRABNK',
  'ALLABNK', 'ALAHBAD',
  'CORPBNK', 'CORPBANK',
  'OBOBC', 'OBCBNK',
  'PSBSMS', 'PSBBNK',
  'INDIAN', 'INDIANBNK',
  // Foreign / other banks
  'CITI', 'CITIBNK', 'STANCH', 'SCBNK', 'HSBC', 'DBS', 'KVB', 'DBSBNK',
  'BARODA', 'BAROBNK',
  // UPI / FinTech apps
  'PAYTM', 'PYTMMB', 'PAYTMSMS',
  'GPAY', 'GOOGLEPAY',
  'PHONEPE', 'PHONPE',
  'BHARATPE', 'BHIMAPP', 'BHIMUPI',
  'AMAZONPAY', 'AMZNPAY',
  'CRED', 'FAMPAY', 'SLICE', 'POSTPE',
  'MOBIKWIK', 'FREECHARGE',
  'LAZYP', 'LAZYPAY',
  'JUPITER', 'FISDOM', 'NIYO', 'NIYOBNK',
};

// ── Debit keywords (UPI / student expense context) ─────────────────────────────
// Only messages that match these are considered for parsing.
final _debitWords = RegExp(
  r'\b(debit(?:ed)?|spent|paid|payment(?:\s+of)?|purchase(?:d)?|charged|'
  r'withdrawn|deducted|sent|pos|mandate|auto.?pay|emi|'
  r'standing\s+instruction|si\s+executed|ecs\s+debit|neft\s+dr|imps\s+dr|'
  r'upi|txn)\b',
  caseSensitive: false,
);

// ── Ignore keywords — messages containing any of these are always skipped ──────
// Covers credit signals, OTPs, promotions, loan/insurance spam, and rewards.
final _ignoreWords = RegExp(
  r'\b(credit(?:ed)?|received|refund(?:ed)?|cashback|cash\s*back|'
  r'salary|income|reward|interest\s+credited|neft\s+cr|imps\s+cr|'
  r'reversed?\s+to|deposited|'
  r'otp|one.?time\s+password|never\s+share\s+your|'
  r'a\/c\s+created|account\s+created|nominee|fd\s+book|fd\s+open|'
  r'kyc|login\s+alert|lucky\s+draw|pre.?approv|'
  r'loan\s+offer|loan\s+approv|personal\s+loan|home\s+loan|'
  r'insurance|promo|offer|discount|earn\s+rewards|win|congratul|'
  r'click\s+here|failed|declined|blocked|insufficient\s+funds|'
  r'cancelled|bounced|unsuccessful|failure|reversed)\b',
  caseSensitive: false,
);

// ── Amount patterns (ordered best-first) ──────────────────────────────────────
final _amountPatterns = [
  // Standard prefix: Rs./INR/₹
  RegExp(r'(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d{0,2})', caseSensitive: false),
  // Standard suffix: 500 Rs / 500 INR
  RegExp(r'([\d,]+\.?\d{0,2})\s*(?:Rs\.?|INR|₹)', caseSensitive: false),
  // Amt: / Amount: prefix
  RegExp(r'(?:Amt|Amount)\s*:?\s*([\d,]+\.?\d{0,2})', caseSensitive: false),
  // for INR500 (IOB style)
  RegExp(r'for\s+(?:INR|Rs\.?|₹)\s*([\d,]+\.?\d{0,2})', caseSensitive: false),
  // Indian vernacular: 500 only / 500/-
  RegExp(r'([\d,]+\.?\d{0,2})\s*(?:only|\/-)(?:\b|$)', caseSensitive: false),
];

// ── Bank-format template regexes ──────────────────────────────────────────────
class _BankTemplate {
  final String bankName;
  final RegExp pattern;
  final int amountGroup;
  final int? merchantGroup;
  const _BankTemplate(
      this.bankName, this.pattern, this.amountGroup, this.merchantGroup);
}

final _bankTemplates = <_BankTemplate>[
  // ── HDFC Bank ────────────────────────────────────────────────────────────────
  _BankTemplate(
    'HDFC Bank',
    RegExp(
      r'(?:HDFC\s*(?:Bank|Bk|BK))\s*(?:A/c|a/c|Account|Acct)?\s*[X*\d]+\s+(?:is\s+)?debited\s+(?:with\s+)?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    1, null,
  ),
  // ── SBI ───────────────────────────────────────────────────────────────────────
  _BankTemplate(
    'SBI',
    RegExp(
      r'(?:State\s*Bank\s*of\s*India|SBI)\b.{0,60}debited\s+by\s+(?:Rs\.?|INR|₹)?\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    1, null,
  ),
  // ── ICICI Bank ────────────────────────────────────────────────────────────────
  _BankTemplate(
    'ICICI Bank',
    RegExp(
      r'(?:ICICI\s*(?:Bank|Bk)?)\s*(?:Acct|A/c|Account)?[X*\d\s]*debited\s+(?:for\s+)?(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    1, null,
  ),
  // ── Axis Bank ─────────────────────────────────────────────────────────────────
  _BankTemplate(
    'Axis Bank',
    RegExp(
      r'(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d{0,2})\s+debited\s+from\s+(?:Axis\s*(?:Bank|Bk))',
      caseSensitive: false,
    ),
    1, null,
  ),
  // ── Punjab National Bank ──────────────────────────────────────────────────────
  _BankTemplate(
    'Punjab National Bank',
    RegExp(
      r'debited.{0,15}?(?:Rs\.?|INR|₹)?\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    1, null,
  ),
  // ── Bank of India ─────────────────────────────────────────────────────────────
  _BankTemplate(
    'Bank of India',
    RegExp(
      r'debited.{0,15}?(?:Rs\.?|INR|₹)?\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    1, null,
  ),
  // ── Bank of Baroda ────────────────────────────────────────────────────────────
  _BankTemplate(
    'Bank of Baroda',
    RegExp(
      r'debited.{0,15}?(?:Rs\.?|INR|₹)?\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    1, null,
  ),
  // ── Canara Bank ───────────────────────────────────────────────────────────────
  _BankTemplate(
    'Canara Bank',
    RegExp(
      r'(?:debited|debit).{0,15}?(?:Rs\.?|INR|₹)?\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    1, null,
  ),
  // ── Indian Overseas Bank ──────────────────────────────────────────────────────
  _BankTemplate(
    'Indian Overseas Bank',
    RegExp(
      r'debited\s+for\s+payee\s+([A-Za-z0-9&@._\-\s]{2,40}?)(?:\s+for|\s+by)?\s+(?:INR|Rs\.?|₹)\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    2, 1,
  ),
  // ── Union Bank ────────────────────────────────────────────────────────────────
  _BankTemplate(
    'Union Bank',
    RegExp(
      r'(?:Union\s*Bank(?:\s*of\s*India)?|UBIBNK|UNIONBNK)\b.{0,60}debited\s+(?:Rs\.?|INR|₹)?\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    1, null,
  ),
  // ── Kotak Bank ────────────────────────────────────────────────────────────────
  _BankTemplate(
    'Kotak Bank',
    RegExp(
      r'(?:Kotak\s*(?:Mahindra\s*)?Bank|KOTAKBK)\b.{0,60}debited\s+(?:Rs\.?|INR|₹)?\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    1, null,
  ),
  // ── Yes Bank ──────────────────────────────────────────────────────────────────
  _BankTemplate(
    'Yes Bank',
    RegExp(
      r'(?:Yes\s*Bank|YESBNK)\b.{0,60}debited\s+(?:Rs\.?|INR|₹)?\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    1, null,
  ),
  // ── IDFC First Bank ───────────────────────────────────────────────────────────
  _BankTemplate(
    'IDFC First Bank',
    RegExp(
      r'(?:IDFC\s*(?:First\s*)?Bank|IDFCBK)\b.{0,60}debited\s+(?:Rs\.?|INR|₹)?\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    1, null,
  ),
  // ── Federal Bank ──────────────────────────────────────────────────────────────
  _BankTemplate(
    'Federal Bank',
    RegExp(
      r'(?:Federal\s*Bank)\b.{0,60}debited\s+(?:Rs\.?|INR|₹)?\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    1, null,
  ),
  // ── RBL Bank ──────────────────────────────────────────────────────────────────
  _BankTemplate(
    'RBL Bank',
    RegExp(
      r'(?:RBL\s*Bank|RBLBNK)\b.{0,60}debited\s+(?:Rs\.?|INR|₹)?\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    1, null,
  ),
  // ── Paytm ─────────────────────────────────────────────────────────────────────
  _BankTemplate(
    'Paytm',
    RegExp(
      r'(?:Paytm\s*(?:Payments?\s*Bank)?)\b.{0,60}(?:debited|paid|sent)\s+(?:Rs\.?|INR|₹)?\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    1, null,
  ),
  // ── Generic / catch-all UPI debit ─────────────────────────────────────────────
  _BankTemplate(
    '',
    RegExp(
      r'(?:Your\s+)?(?:A\/C|a\/c|Account|Acct)\s+[X*\dA-Z]{4,20}\s+(?:has\s+been\s+)?debited\s+(?:Rs\.?|INR|₹)?\s*([\d,]+\.?\d{0,2})',
      caseSensitive: false,
    ),
    1, null,
  ),
];

// ── Merchant extraction patterns ──────────────────────────────────────────────
final _merchantPatterns = [
  // UPI VPA: user@bankname
  RegExp(r'\b([a-zA-Z0-9._\-]+@[a-zA-Z]{2,20})\b'),
  // IOB / generic: "debited for payee MERCHANT"
  RegExp(
    r'(?:for\s+payee|payee\s+name(?:\s*:)?)\s+([A-Za-z0-9&@._\-\s]{2,40}?)(?:\s+(?:on|via|at|using|UPI|Ref|VPA|A\/C|ref\.)|[.,]|$)',
    caseSensitive: false,
  ),
  // "Merchant: XYZ"
  RegExp(
    r'Merchant\s*[:\-]\s*([A-Za-z0-9&\s._\-]{2,40})',
    caseSensitive: false,
  ),
  // "to/at/for/towards MERCHANT"
  RegExp(
    r'(?:to|at|for|towards)\s+([A-Za-z0-9&@._\-\s]{2,40}?)(?:\s+(?:on|via|at|using|UPI|Ref|VPA|A\/C|ref\.)|[.,]|$)',
    caseSensitive: false,
  ),
  // POS terminal
  RegExp(
    r'POS\s+(?:at\s+)?([A-Z0-9\s]{4,35})',
    caseSensitive: false,
  ),
];

// ── Merchant noise words to strip ─────────────────────────────────────────────
final _merchantNoise = RegExp(
  r'\s*(UPI|IMPS|NEFT|RTGS|Ref|VPA|A\/C|AC|a\/c\s+no\.?|a\/c|on\s+\d|at\s+\d|using|via|the|your|from|is)\s*$',
  caseSensitive: false,
);

final _cardDigits = RegExp(r'[Xx*]{4,}|\b\d{4}\b');

// ── Balance / available balance keywords ──────────────────────────────────────
final _balanceWords =
    RegExp(r'\b(bal(?:ance)?|avl|avail(?:able)?|limit|lmt)\b', caseSensitive: false);

// ── Student-focused category keyword mapping ──────────────────────────────────
// Categories: Food | Shopping | Travel | Bills | Education | Entertainment | Health | Others
const _categoryKeywords = <String, List<String>>{
  'Food': [
    'zomato', 'swiggy', 'dominos', 'kfc', 'mcdonalds', 'subway', 'pizza',
    'burger', 'starbucks', 'cafe', 'restaurant', 'food', 'eat',
    'biryani', 'haldiram', 'bikanervala', 'blinkit', 'zepto', 'dunzo',
    'groceries', 'grocery', 'bigbasket', 'grofer', 'instamart', 'bbnow',
    'dmart', 'reliance fresh', 'sweet', 'bakery', 'licious', 'freshtohome',
    'canteen', 'mess', 'tiffin', 'dabba', 'hotel', 'dhaba', 'tea', 'coffee',
    'chai', 'dairy', 'milk', 'amul', 'nandini', 'mother dairy', 'supermarket',
    'sahakari', 'bhandar', 'more mega store', 'spencer',
  ],
  'Shopping': [
    'amazon', 'flipkart', 'myntra', 'meesho', 'ajio', 'nykaa', 'firstcry',
    'snapdeal', 'tatacliq', 'shopping', 'store', 'mart', 'mall',
    'decathlon', 'zara', 'h&m', 'max', 'pantaloons', 'lifestyle', 'trends',
    'shoppers stop', 'croma', 'reliance digital', 'lenskart', 'titan',
    'apparel', 'clothing', 'footwear', 'shoes', 'fashion', 'zudio',
    'bata', 'puma', 'nike', 'adidas', 'miniso',
  ],
  'Travel': [
    'uber', 'ola', 'rapido', 'namma yatri', 'indrive', 'blu smart', 'irctc',
    'train', 'railway', 'bus', 'flight', 'makemytrip', 'yatra', 'easemytrip',
    'cleartrip', 'redbus', 'ixigo', 'metro', 'toll', 'fastag', 'parking',
    'petrol', 'diesel', 'cng', 'fuel', 'hpcl', 'iocl', 'bpcl', 'indian oil',
    'shell', 'auto', 'cab', 'taxi', 'transport', 'kstdc', 'ksrtc', 'bmc',
    'indigo', 'air india', 'spicejet', 'akasa', 'agoda', 'oyo', 'nayara',
  ],
  'Bills': [
    'electricity', 'water', 'gas', 'broadband', 'jio', 'airtel', 'vi ',
    'vodafone', 'bsnl', 'tata sky', 'tata play', 'dth', 'recharge',
    'postpaid', 'prepaid', 'internet', 'bescom', 'msedcl', 'tata power',
    'adani', 'bses', 'uppcl', 'tneb', 'torrent', 'act fibernet', 'hathway',
    'excitel', 'wifi', 'bill', 'rent', 'maintenance', 'insurance', 'lic',
    'emi', 'loan repayment', 'premium',
  ],
  'Entertainment': [
    'netflix', 'hotstar', 'spotify', 'prime', 'youtube', 'subscription',
    'bookmyshow', 'pvr', 'inox', 'cinepolis', 'movie', 'cinema', 'theater',
    'gaming', 'steam', 'playstation', 'xbox', 'epic games', 'pubg', 'bgmi',
    'event', 'concert', 'amusement', 'water park', 'wonderla',
  ],
  'Education': [
    'school', 'college', 'university', 'byju', 'unacademy', 'vedantu',
    'physics wallah', 'udemy', 'coursera', 'upgrad', 'fees', 'tuition',
    'books', 'stationery', 'notebook', 'pen', 'pencil', 'exam', 'coaching',
    'institute', 'library', 'hostel', 'admission', 'print', 'xerox',
  ],
  'Health': [
    'pharmacy', 'apollo', 'pharmeasy', '1mg', 'netmeds', 'medplus',
    'hospital', 'clinic', 'doctor', 'medical', 'medicine', 'health',
    'practo', 'diagnostic', 'pathology', 'lab', 'gym', 'fitness', 'curefit',
  ],
};

// ─────────────────────────────────────────────────────────────────────────────
// ParsedExpense — result model
// ─────────────────────────────────────────────────────────────────────────────

/// Result of parsing a single UPI debit SMS.
class ParsedExpense {
  final double amount;
  final String merchant;
  final String category;
  final String? bank;
  final DateTime timestamp;
  final int confidence; // 0–100
  final String hash;

  const ParsedExpense({
    required this.amount,
    required this.merchant,
    required this.category,
    this.bank,
    required this.timestamp,
    required this.confidence,
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
        confidence: confidence,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SmsParserService — Student Money Manager edition
// ─────────────────────────────────────────────────────────────────────────────
//
// Only debit / UPI payment messages are accepted.
// Credit, OTP, loan, insurance, promo, and reward messages are always rejected.
//
// Scoring (0-base, additive):
//   +35  amount extracted
//   +25  debit keyword present
//   +20  trusted sender header
//   +10  merchant extracted
//   +10  bank-format template matched
// ─────────────────────────────────────────────────────────────────────────────
//  ≥70  auto-add
//  40–69 mark as "Needs Review"
//  <40  reject (return null)
class SmsParserService {
  const SmsParserService();

  /// Returns null if the message is not a valid UPI debit SMS.
  ParsedExpense? parse(String body, String? sender, DateTime timestamp) {
    // ── Step 1: Hard length check ────────────────────────────────────────
    if (body.trim().length < 30) return null;

    // ── Step 2: Ignore-list check (credit, OTP, promo, loan, etc.) ───────
    // This is checked BEFORE the debit keyword check so that messages
    // containing BOTH a debit word and a credit/ignore word (e.g. reversal
    // confirmations) are safely rejected.
    if (_ignoreWords.hasMatch(body)) return null;

    // ── Step 3: Debit keyword must be present ────────────────────────────
    if (!_debitWords.hasMatch(body)) return null;

    // ── Step 4: Amount extraction ─────────────────────────────────────────
    final double? rawAmount = _extractAmount(body);
    if (rawAmount == null) return null;
    double amount = rawAmount;

    // ── Step 5: Confidence scoring ────────────────────────────────────────
    int score = 35; // amount extracted
    score += 25;    // debit keyword confirmed

    final normalizedSender =
        sender?.toUpperCase().replaceAll(RegExp(r'[-\s]'), '') ?? '';
    final isTrusted =
        _trustedSenders.any((s) => normalizedSender.contains(s));
    if (isTrusted) score += 20;

    // ── Step 6: Bank-format template matching ─────────────────────────────
    String? templateBank;
    String? templateMerchant;
    for (final tpl in _bankTemplates) {
      final m = tpl.pattern.firstMatch(body);
      if (m != null) {
        final tplAmtRaw = m.group(tpl.amountGroup)?.replaceAll(',', '');
        final double? tplAmt =
            tplAmtRaw != null ? double.tryParse(tplAmtRaw) : null;
        if (tplAmt != null && tplAmt > 0) {
          amount = tplAmt;
        }
        if (tpl.merchantGroup != null) {
          final raw = m.group(tpl.merchantGroup!)?.trim() ?? '';
          if (raw.length >= 2) templateMerchant = _toTitleCase(raw);
        }
        if (tpl.bankName.isNotEmpty) templateBank = tpl.bankName;
        score += 10;
        break;
      }
    }

    // ── Step 7: Merchant extraction ───────────────────────────────────────
    String merchant = templateMerchant ?? _extractMerchant(body);
    if (merchant != 'Unknown') score += 10;

    // ── Step 8: Reject below threshold ───────────────────────────────────
    if (score < 40) return null;

    // ── Step 9: Category + bank ────────────────────────────────────────────
    final category = _inferCategory(body, merchant);
    final bank = templateBank ?? _inferBank(normalizedSender, body);

    // ── Step 10: Deduplication hash (merchant + amount + minute) ──────────
    final minuteKey =
        '${timestamp.year}${timestamp.month}${timestamp.day}'
        '${timestamp.hour}${timestamp.minute}';
    final rawHash = '$merchant|${amount.toStringAsFixed(2)}|$minuteKey';
    final hash = md5.convert(utf8.encode(rawHash)).toString();

    return ParsedExpense(
      amount: amount,
      merchant: merchant,
      category: category,
      bank: bank,
      timestamp: timestamp,
      confidence: score.clamp(0, 100),
      hash: hash,
    );
  }

  // ── Amount extraction ──────────────────────────────────────────────────────

  double? _extractAmount(String body) {
    final debitMatches = _debitWords.allMatches(body).toList();
    final balMatches = _balanceWords.allMatches(body).toList();

    double? best;
    int minDist = 999999;

    for (final pattern in _amountPatterns) {
      for (final m in pattern.allMatches(body)) {
        final raw = m.group(1)!.replaceAll(',', '');
        final candidate = double.tryParse(raw);
        if (candidate == null || candidate <= 0 || candidate > 1000000) continue;

        final idx = m.start;

        // Skip if a balance keyword appears within 80 chars AFTER this amount
        bool nearBalance = false;
        for (final bm in balMatches) {
          final dist = bm.start - idx;
          if (dist > 3 && dist < 80) {
            nearBalance = true;
            break;
          }
        }
        if (nearBalance) continue;

        int dist = 999999;
        for (final dm in debitMatches) {
          final d = (dm.start - idx).abs();
          if (d < dist) dist = d;
        }

        if (dist < minDist) {
          minDist = dist;
          best = candidate;
        }
      }
    }

    // Fallback: first valid amount
    if (best == null) {
      for (final pattern in _amountPatterns) {
        final m = pattern.firstMatch(body);
        if (m != null) {
          final raw = m.group(1)!.replaceAll(',', '');
          final v = double.tryParse(raw);
          if (v != null && v > 0) {
            best = v;
            break;
          }
        }
      }
    }

    return best;
  }

  // ── Merchant extraction ────────────────────────────────────────────────────

  String _extractMerchant(String body) {
    for (final pattern in _merchantPatterns) {
      final m = pattern.firstMatch(body);
      if (m != null) {
        final raw = (m.group(1) ?? '').trim();
        final cleaned = raw
            .replaceAll(_merchantNoise, '')
            .replaceAll(_cardDigits, '')
            .trim();
        if (cleaned.length >= 2 && cleaned.length <= 50) {
          return _toTitleCase(cleaned);
        }
      }
    }
    return 'Unknown';
  }

  // ── Category inference ─────────────────────────────────────────────────────
  // Returns one of: Food | Shopping | Travel | Bills | Education | Others

  String _inferCategory(String body, String merchant) {
    final lower = '${body.toLowerCase()} ${merchant.toLowerCase()}';
    for (final entry in _categoryKeywords.entries) {
      if (entry.value.any(lower.contains)) return entry.key;
    }
    return 'Others';
  }

  // ── Bank inference ─────────────────────────────────────────────────────────

  String? _inferBank(String sender, String body) {
    final s = sender.toLowerCase();
    if (s.contains('hdfc')) return 'HDFC Bank';
    if (s.contains('icici')) return 'ICICI Bank';
    if (s.contains('sbi') || s.contains('state bank')) return 'SBI';
    if (s.contains('axis')) return 'Axis Bank';
    if (s.contains('kotak')) return 'Kotak Bank';
    if (s.contains('yes')) return 'Yes Bank';
    if (s.contains('canara') || s.contains('canbk')) return 'Canara Bank';
    if (s.contains('iob') || s.contains('overseas bank')) return 'Indian Overseas Bank';
    if (s.contains('pnb') || s.contains('punjab national')) return 'Punjab National Bank';
    if (s.contains('boi') || s.contains('bank of india')) return 'Bank of India';
    if (s.contains('bob') || s.contains('baroda')) return 'Bank of Baroda';
    if (s.contains('union') || s.contains('ubi')) return 'Union Bank';
    if (s.contains('indian bank') || s.contains('indbnk')) return 'Indian Bank';
    if (sender.contains('CORP') || sender.contains('CORPBNK')) return 'Corporation Bank';
    if (sender.contains('UCO') || sender.contains('UCOBNK')) return 'UCO Bank';
    if (sender.contains('IDBI') || sender.contains('IDBIBNK')) return 'IDBI Bank';
    if (sender.contains('CBI') || sender.contains('CBIBNK')) return 'Central Bank of India';
    if (sender.contains('FEDERAL')) return 'Federal Bank';
    if (sender.contains('RBL') || sender.contains('RBLBNK')) return 'RBL Bank';
    if (sender.contains('IDFC') || sender.contains('IDFCBK')) return 'IDFC First Bank';
    if (sender.contains('KVB')) return 'Karur Vysya Bank';
    if (sender.contains('PAYTM') || sender.contains('PYTM')) return 'Paytm';
    if (sender.contains('GPAY') || sender.contains('GOOGLE')) return 'Google Pay';
    if (sender.contains('PHONE') || sender.contains('PHONPE')) return 'PhonePe';
    if (sender.contains('AMAZON') || sender.contains('AMZN')) return 'Amazon Pay';

    // Fallback: scan body
    final lower = body.toLowerCase();
    if (lower.contains('hdfc bank')) return 'HDFC Bank';
    if (lower.contains('icici bank')) return 'ICICI Bank';
    if (lower.contains('state bank of india') || lower.contains('sbi')) return 'SBI';
    if (lower.contains('axis bank')) return 'Axis Bank';
    if (lower.contains('kotak')) return 'Kotak Bank';
    if (lower.contains('punjab national bank') || lower.contains('pnb')) return 'Punjab National Bank';
    if (lower.contains('bank of india')) return 'Bank of India';
    if (lower.contains('bank of baroda')) return 'Bank of Baroda';
    if (lower.contains('canara bank')) return 'Canara Bank';
    if (lower.contains('indian overseas bank') || lower.contains('iob')) return 'Indian Overseas Bank';
    if (lower.contains('union bank')) return 'Union Bank';
    if (lower.contains('idfc')) return 'IDFC First Bank';
    if (lower.contains('federal bank')) return 'Federal Bank';
    if (lower.contains('yes bank')) return 'Yes Bank';
    if (lower.contains('rbl bank')) return 'RBL Bank';

    return null;
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  String _toTitleCase(String s) => s
      .split(' ')
      .map((w) => w.isEmpty
          ? w
          : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}
