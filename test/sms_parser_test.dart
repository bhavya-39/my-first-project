// Pure-Dart unit tests for SmsParserService — Student Money Manager edition.
// Run with: flutter test test/sms_parser_test.dart
//
// No Firebase, no platform channels — these tests run on any machine.
//
// Valid categories: Food | Shopping | Travel | Bills | Education | Others

import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/services/sms_parser_service.dart';

void main() {
  const parser = SmsParserService();
  final now = DateTime(2026, 3, 25, 12, 0);

  // ── Helper ────────────────────────────────────────────────────────────────
  ParsedExpense? parse(String body, {String sender = 'HDFCBK'}) =>
      parser.parse(body, sender, now);

  // ── HDFC Bank ─────────────────────────────────────────────────────────────
  group('HDFC Bank', () {
    test('standard debit with balance — picks transaction amount', () {
      const msg =
          'HDFC Bank A/c XX1234 debited with Rs.1250.00 on 25-Mar-26. '
          'Avl Bal: Rs.18500.00. UPI Ref 123456789.';
      final r = parse(msg, sender: 'HDFCBK');
      expect(r, isNotNull);
      expect(r!.amount, 1250.00);
      expect(r.bank, 'HDFC Bank');
      expect(r.confidence, greaterThanOrEqualTo(70));
    });

    test('UPI VPA merchant extracted', () {
      const msg =
          'HDFC Bank A/c XX1234 debited with Rs.499.00. UPI transfer to '
          'zomato@icici. Avl Bal Rs.5000.';
      final r = parse(msg, sender: 'HDFCBK');
      expect(r, isNotNull);
      expect(r!.merchant.toLowerCase(), contains('zomato'));
    });

    test('credit / refund message is ignored (debit-only parser)', () {
      const msg =
          'HDFC Bank A/c XX1234 credited with Rs.299.00 on 25-Mar-26. '
          'Refund from NETFLIX. Avl Bal Rs.5299.';
      expect(parse(msg, sender: 'HDFCBK'), isNull);
    });
  });

  // ── SBI ────────────────────────────────────────────────────────────────────
  group('SBI', () {
    test('SBI debit message — correct amount', () {
      const msg =
          'State Bank of India: Your a/c XXXXXX1234 has been debited by '
          'Rs.2000.00 on 25Mar26. If not done by you call 1800112211.';
      final r = parse(msg, sender: 'SBIINB');
      expect(r, isNotNull);
      expect(r!.amount, 2000.00);
      expect(r.bank, 'SBI');
    });

    test('SBI salary credited is ignored (debit-only parser)', () {
      const msg =
          'INR 35000.00 credited to SBI A/c XX5678 on 25-Mar. '
          'Info: SALARY MAR 2026.';
      expect(parse(msg, sender: 'SBIINB'), isNull);
    });
  });

  // ── ICICI Bank ────────────────────────────────────────────────────────────
  group('ICICI Bank', () {
    test('ICICI debit for Rs — amount and bank correct', () {
      const msg =
          'ICICI Bank Acct XX9999 debited for Rs 750.00 on 25-Mar-26 '
          'towards Uber. Avl bal Rs 12000.';
      final r = parse(msg, sender: 'ICICIB');
      expect(r, isNotNull);
      expect(r!.amount, 750.00);
      expect(r.bank, 'ICICI Bank');
    });

    test('ICICI refund is ignored (debit-only parser)', () {
      const msg =
          'Dear Customer, Rs.199.00 has been credited to your ICICI Bank '
          'account XX9999 as a refund from AMAZON. Avl bal Rs 6199.';
      expect(parse(msg, sender: 'ICICIB'), isNull);
    });
  });

  // ── Axis Bank ─────────────────────────────────────────────────────────────
  group('Axis Bank', () {
    test('Axis debit amount extracted', () {
      const msg =
          'Rs 600.00 debited from Axis Bank A/c XX4321 for UPI payment to '
          'swiggy@axisbank on 25-Mar-26.';
      final r = parse(msg, sender: 'AXISBK');
      expect(r, isNotNull);
      expect(r!.amount, 600.00);
      expect(r.bank, 'Axis Bank');
    });
  });

  // ── Punjab National Bank ──────────────────────────────────────────────────
  group('Punjab National Bank', () {
    test('PNB debit SMS parsed correctly', () {
      const msg =
          'Punjab National Bank: Your A/C XXXXXX7777 has been debited '
          'Rs 4500.00 on 25-03-26. Avl Bal: Rs 15500.00.';
      final r = parse(msg, sender: 'PNBSMS');
      expect(r, isNotNull);
      expect(r!.amount, 4500.00);
      expect(r.bank, 'Punjab National Bank');
    });
  });

  // ── Indian Overseas Bank ──────────────────────────────────────────────────
  group('Indian Overseas Bank (IOB)', () {
    test('IOB payee pattern — merchant and amount both extracted', () {
      const msg =
          'Indian Overseas Bank: Your A/c XX2211 debited for payee '
          'SWIGGY IT PVT LTD for INR 340.00 on 25-03-26. Avl Bal INR 8660.00.';
      final r = parse(msg, sender: 'IOBSMS');
      expect(r, isNotNull);
      expect(r!.amount, 340.00);
      expect(r.merchant.toLowerCase(), contains('swiggy'));
      expect(r.bank, 'Indian Overseas Bank');
    });
  });

  // ── Paytm / UPI apps ──────────────────────────────────────────────────────
  group('Paytm UPI', () {
    test('Paytm sent message — amount and debit type', () {
      const msg =
          'Paytm: Rs.120.00 paid to RAPIDO using UPI on 25-Mar-26. '
          'UPI Ref No. 987654321.';
      final r = parse(msg, sender: 'PAYTM');
      expect(r, isNotNull);
      expect(r!.amount, 120.00);
    });

    test('Google Pay UPI debit via VPA', () {
      const msg =
          'Rs.80 deducted from your account via Google Pay UPI to '
          'merchant@okicici. Ref: 111222333.';
      final r = parse(msg, sender: 'GPAY');
      expect(r, isNotNull);
      expect(r!.amount, 80.0);
      expect(r.merchant.toLowerCase(), contains('merchant@okicici'));
    });
  });

  // ── Noise / rejection cases ────────────────────────────────────────────────
  group('Noise rejection', () {
    test('OTP message rejected', () {
      const msg = 'Your OTP for bank login is 382940. Never share your OTP.';
      expect(parse(msg, sender: 'HDFCBK'), isNull);
    });

    test('KYC alert rejected', () {
      const msg =
          'Dear customer, your KYC is pending. Please complete it at the '
          'nearest branch to avoid account suspension.';
      expect(parse(msg, sender: 'SBIINB'), isNull);
    });

    test('Promotional loan offer rejected', () {
      const msg =
          'Congratulations! You are pre-approved for a Rs.5,00,000 personal '
          'loan. Click here to apply now.';
      expect(parse(msg, sender: 'HDFCBK'), isNull);
    });

    test('Failed transaction rejected', () {
      const msg =
          'Your UPI transaction of Rs.500 to merchant@upi has failed due to '
          'insufficient funds. No amount was debited.';
      expect(parse(msg, sender: 'ICICIB'), isNull);
    });

    test('Bounced autopay rejected', () {
      const msg =
          'Your Autopay of Rs.199.00 to NETFLIX was unsuccessful due to '
          'technical issues. Please retry.';
      expect(parse(msg, sender: 'HDFCBK'), isNull);
    });

    test('Very short message rejected', () {
      expect(parse('Rs.100 paid.', sender: 'HDFCBK'), isNull);
    });

    test('Account creation alert rejected', () {
      const msg =
          'Your ICICI Bank savings account XX1234 has been created. '
          'Welcome to ICICI Bank!';
      expect(parse(msg, sender: 'ICICIB'), isNull);
    });

    test('Cashback message rejected', () {
      const msg =
          'HDFC Bank: Rs.50 cashback credited to your A/c XX1234 on 25-Mar-26. '
          'UPI Ref 555666777.';
      expect(parse(msg, sender: 'HDFCBK'), isNull);
    });

    test('Reward message rejected', () {
      const msg =
          'Congratulations! You have earned Rs.100 as reward points on your '
          'ICICI Bank Debit Card for spending Rs.1000.';
      expect(parse(msg, sender: 'ICICIB'), isNull);
    });

    test('Insurance offer rejected', () {
      const msg =
          'Get life insurance cover of Rs.50 lakh for just Rs.500/month. '
          'Click here to buy now.';
      expect(parse(msg, sender: 'HDFCBK'), isNull);
    });

    test('Message with debit AND credit keywords → rejected', () {
      // Reversal confirmation: contains both "debited" and "credited"
      const msg =
          'HDFC Bank: Earlier debit of Rs.200 reversed. Rs.200 credited '
          'back to A/c XX1234. Avl Bal Rs.5200.';
      expect(parse(msg, sender: 'HDFCBK'), isNull);
    });
  });

  // ── Category inference (student-focused) ──────────────────────────────────
  group('Category inference', () {
    test('Swiggy order → Food', () {
      const msg =
          'HDFC Bank A/c XX1234 debited with Rs.350.00. '
          'UPI to swiggy@icici. Avl Bal Rs.4650.';
      final r = parse(msg);
      expect(r?.category, 'Food');
    });

    test('Uber ride → Travel', () {
      const msg =
          'HDFC Bank A/c XX1234 debited with Rs.180.00. '
          'UPI to uber@hdfcbank. Avl Bal Rs.4820.';
      final r = parse(msg);
      expect(r?.category, 'Travel');
    });

    test('Amazon → Shopping', () {
      const msg =
          'HDFC Bank A/c XX1234 debited with Rs.499.00 for AMAZON. '
          'Avl Bal Rs.4501.';
      final r = parse(msg);
      expect(r?.category, 'Shopping');
    });

    test('Mobile recharge / Jio → Bills', () {
      const msg =
          'HDFC Bank A/c XX1234 debited with Rs.239.00 for Jio recharge. '
          'Avl Bal Rs.4200.';
      final r = parse(msg);
      expect(r?.category, 'Bills');
    });

    test('College fees → Education', () {
      const msg =
          'HDFC Bank A/c XX1234 debited with Rs.15000.00 for college fees '
          'payment. Avl Bal Rs.5000.';
      final r = parse(msg);
      expect(r?.category, 'Education');
    });

    test('Unknown merchant → Others', () {
      const msg =
          'HDFC Bank A/c XX1234 debited with Rs.100.00 UPI to '
          'randommerchant@xyz. Avl Bal Rs.4900.';
      final r = parse(msg);
      expect(r?.category, 'Others');
    });

    test('Category is never Transfers', () {
      const msg =
          'HDFC Bank A/c XX1234 debited with Rs.500.00. '
          'UPI transfer to friend@oksbi. Avl Bal Rs.4500.';
      final r = parse(msg);
      expect(r?.category, isNot('Transfers'));
    });

    test('Category is never Income', () {
      const msg =
          'HDFC Bank A/c XX1234 debited with Rs.200.00. '
          'UPI to merchant@okaxis. Avl Bal Rs.4800.';
      final r = parse(msg);
      expect(r?.category, isNot('Income'));
    });

    test('Salary credit → ignored (debit-only parser)', () {
      const msg =
          'INR 45000.00 credited to SBI A/c XX1234. Info: SALARY MARCH 2026.';
      expect(parse(msg, sender: 'SBIINB'), isNull);
    });
  });

  // ── Deduplication hash stability ──────────────────────────────────────────
  group('Hash stability', () {
    test('Same message same minute → same hash', () {
      const msg =
          'HDFC Bank A/c XX1234 debited with Rs.500.00 on 25-Mar-26. '
          'UPI to test@okhdfc. Avl Bal Rs.4500.';
      final r1 = parse(msg);
      final r2 = parse(msg);
      expect(r1?.hash, r2?.hash);
    });

    test('Different amounts → different hash', () {
      const msg1 =
          'HDFC Bank A/c XX1234 debited with Rs.100.00 on 25-Mar-26. '
          'UPI to test@okhdfc. Avl Bal Rs.4900.';
      const msg2 =
          'HDFC Bank A/c XX1234 debited with Rs.200.00 on 25-Mar-26. '
          'UPI to test@okhdfc. Avl Bal Rs.4800.';
      final r1 = parse(msg1);
      final r2 = parse(msg2);
      expect(r1?.hash, isNot(r2?.hash));
    });
  });
}
