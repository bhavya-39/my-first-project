class Goal {
  String id;
  String goalName;
  double targetAmount;
  double savedAmount;
  String status;

  Goal({
    required this.id,
    required this.goalName,
    required this.targetAmount,
    this.savedAmount = 0.0,
    this.status = 'Active',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'goalName': goalName,
      'targetAmount': targetAmount,
      'savedAmount': savedAmount,
      'status': status,
    };
  }

  factory Goal.fromMap(Map<String, dynamic> map) {
    return Goal(
      id: map['id'] ?? '',
      goalName: map['goalName'] ?? '',
      targetAmount: (map['targetAmount'] ?? 0).toDouble(),
      savedAmount: (map['savedAmount'] ?? 0).toDouble(),
      status: map['status'] ?? 'Active',
    );
  }

  double get progress => targetAmount > 0 ? (savedAmount / targetAmount) : 0.0;
}
