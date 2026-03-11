void main() {
  List<double> amounts = [15.0, 10.0, 105.12, 12.50, 0.0, 100.0, 1.0];

  for (var amount in amounts) {
    double oldWay = (amount / 10).ceil() * 10 - amount;
    double newWay = oldWay == 0 ? 10.0 : oldWay;
    print('Amount: $amount -> Saved: $newWay');
  }
}
