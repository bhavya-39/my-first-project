import 'dart:io';
import 'lib/services/sms_parser_service.dart';

void main() {
  final parser = SmsParserService();
  
  final tests = [
    ("Indian Overseas Bank", "Your a/c XXXXX82 debited for payee MANJUNATH INR 150.00 on 2024-03-12"),
    ("State Bank of India", "Your a/c no. XXXXXXXX3456 is debited by Rs.200.00 on 12Mar24 transfer to Payee"),
    ("Canara Bank", "Your A/c 123X debited by Rs.350.00 on 12-03-24. Avl Bal Rs.400.00"),
    ("Bank of India", "Your A/c no. 1234 is debited for Rs.400.00 on 12/03/24."),
  ];
  
  for (final t in tests) {
    final sender = t.$1;
    final msg = t.$2;
    print("\nTesting sender: \$sender");
    final res = parser.parse(msg, sender, DateTime.now());
    if (res == null) {
      print("RESULT: FAIL (Returned null)");
    } else {
      print("RESULT: SUCCESS | Amount: \${res.amount} | Bank: \${res.bank} | Score Conf: \${res.confidence}");
    }
  }
}

