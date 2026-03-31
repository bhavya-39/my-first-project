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
    name: 'Food',
    icon: Icons.restaurant,
    color: Color(0xFFFF6B6B),
    type: 'expense',
  ),
  const CategoryModel(
    id: 'travel',
    name: 'Travel',
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
    id: 'bills',
    name: 'Bills',
    icon: Icons.receipt_long,
    color: Color(0xFF0EA5E9),
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
    id: 'health',
    name: 'Health',
    icon: Icons.local_hospital,
    color: Color(0xFFEC4899),
    type: 'expense',
  ),
  const CategoryModel(
    id: 'others',
    name: 'Others',
    icon: Icons.more_horiz,
    color: Color(0xFFB2BEC3),
    type: 'expense',
  ),
];
