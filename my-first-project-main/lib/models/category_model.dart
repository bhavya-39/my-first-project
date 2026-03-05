import 'package:flutter/material.dart';

class CategoryModel {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final String type; // 'expense' or 'income'

  const CategoryModel({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.type,
  });
}

// Default Categories
final List<CategoryModel> defaultCategories = [
  // Expenses
  const CategoryModel(
    id: 'food',
    name: 'Food & Dining',
    icon: Icons.restaurant,
    color: Color(0xFFFF6B6B),
    type: 'expense',
  ),
  const CategoryModel(
    id: 'transport',
    name: 'Transport',
    icon: Icons.directions_bus,
    color: Color(0xFF4ECDC4),
    type: 'expense',
  ),
  const CategoryModel(
    id: 'shopping',
    name: 'Shopping',
    icon: Icons.shopping_bag,
    color: Color(0xFFFFD93D),
    type: 'expense',
  ),
  const CategoryModel(
    id: 'entertainment',
    name: 'Entertainment',
    icon: Icons.movie,
    color: Color(0xFF6C5CE7),
    type: 'expense',
  ),
  const CategoryModel(
    id: 'education',
    name: 'Education',
    icon: Icons.school,
    color: Color(0xFF0984E3),
    type: 'expense',
  ),
  const CategoryModel(
    id: 'others',
    name: 'Others',
    icon: Icons.more_horiz,
    color: Color(0xFFB2BEC3),
    type: 'expense',
  ),
  
  // Income
  const CategoryModel(
    id: 'allowance',
    name: 'Allowance',
    icon: Icons.account_balance_wallet,
    color: Color(0xFF00B894),
    type: 'income',
  ),
  const CategoryModel(
    id: 'part_time',
    name: 'Part-time Job',
    icon: Icons.work,
    color: Color(0xFF00CEC9),
    type: 'income',
  ),
  const CategoryModel(
    id: 'gift',
    name: 'Gift',
    icon: Icons.card_giftcard,
    color: Color(0xFFFD79A8),
    type: 'income',
  ),
];
