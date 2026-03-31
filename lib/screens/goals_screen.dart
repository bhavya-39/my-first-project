import 'package:flutter/material.dart';
import '../models/goal_model.dart';
import '../models/expense_model.dart';
import '../database/local_database.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({Key? key}) : super(key: key);

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  List<Goal> _goals = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGoals();
  }

  /// Load goals from the database
  Future<void> _loadGoals() async {
    final dbGoals = await LocalDatabase.instance.getAllGoals();
    setState(() {
      _goals = dbGoals;
      _isLoading = false;
    });
  }

  /// Add a new goal to the database
  Future<void> _addGoal(String name, double targetAmount) async {
    final newGoal = Goal(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      goalName: name,
      targetAmount: targetAmount,
      savedAmount: 0.0,
      status: 'Active',
    );
    await LocalDatabase.instance.insertGoal(newGoal);
    _loadGoals();
  }

  /// Withdraw from goal (Resets savedAmount to 0 and updates the database)
  Future<void> _withdrawGoal(Goal goal) async {
    // Return the money to the Piggy Bank so it's not lost
    if (goal.savedAmount > 0) {
      await LocalDatabase.instance.insertSavings(PiggyBankEntry(
        amount: goal.savedAmount,
        date: DateTime.now(),
      ));
    }

    goal.savedAmount = 0.0;
    goal.status = 'Active';
    await LocalDatabase.instance.updateGoal(goal);
    
    _loadGoals();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Withdrew funds from ${goal.goalName}. Reset to ₹0.'),
          backgroundColor: Colors.blueAccent,
        ),
      );
    }
  }

  /// Bottom dialog to create a new goal
  void _showAddGoalDialog() {
    final nameController = TextEditingController();
    final targetController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create New Goal',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Goal Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.flag),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: targetController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Target Amount (₹)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.currency_rupee),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Goal'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final name = nameController.text.trim();
                    final target = double.tryParse(targetController.text) ?? 0.0;

                    if (name.isNotEmpty && target > 0) {
                      _addGoal(name, target);
                      Navigator.pop(context);
                    }
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  /// Determine the progress bar color
  Color _getProgressColor(double progress) {
    if (progress < 0.50) {
      return Colors.blue;
    } else if (progress <= 0.80) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('My Savings Goals', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        actions: [
          IconButton(
            icon: const Icon(Icons.savings_outlined, color: Colors.lightBlue),
            onPressed: () {
               ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Virtual Piggy Bank active!'))
               );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _goals.isEmpty
              ? _buildEmptyState()
              : _buildGoalsList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddGoalDialog,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Goal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E90FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🎯', style: TextStyle(fontSize: 80)),
          const SizedBox(height: 24),
          Text(
            'No goals yet',
            style: TextStyle(
              fontSize: 22, 
              color: isDark ? Colors.white : Colors.black87, 
              fontWeight: FontWeight.bold
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Create a target and your piggy bank savings will automatically help you reach it!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey, 
                height: 1.5,
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildGoalsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _goals.length,
      itemBuilder: (context, index) {
        final goal = _goals[index];
        final bool isCompleted = goal.savedAmount >= goal.targetAmount;
        final double progress = goal.progress.clamp(0.0, 1.0);
        final Color progressColor = _getProgressColor(progress);

        return Card(
          elevation: 3,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Goal Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isCompleted ? Icons.check_circle : Icons.flag,
                          color: isCompleted ? Colors.green : Colors.blueAccent,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          goal.goalName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (isCompleted)
                      const Text(
                        'Completed!',
                        style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                      )
                    else
                      Text(
                        '${(progress * 100).toStringAsFixed(0)}% completed',
                        style: TextStyle(color: progressColor, fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Amount Text
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Saved: ₹${goal.savedAmount.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Target: ₹${goal.targetAmount.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 15, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.grey[200],
                    color: progressColor,
                  ),
                ),
                
                // Withdraw Button
                if (goal.savedAmount > 0) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => _withdrawGoal(goal),
                      icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                      label: const Text('Withdraw'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ]
              ],
            ),
          ),
        );
      },
    );
  }
}
