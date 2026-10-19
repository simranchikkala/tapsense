import 'package:flutter/material.dart';

class Category {
  final String id;
  final String name;
  final IconData icon;
  final Color color;

  const Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
  });
}

const List<Category> kCategories = [
  Category(id: 'food',        name: 'Food & Drinks',  icon: Icons.restaurant,       color: Color(0xFFFF6B6B)),
  Category(id: 'transport',   name: 'Transport',      icon: Icons.directions_bus,   color: Color(0xFF4ECDC4)),
  Category(id: 'shopping',    name: 'Shopping',       icon: Icons.shopping_bag,     color: Color(0xFFFFBE0B)),
  Category(id: 'groceries',   name: 'Groceries',      icon: Icons.local_grocery_store, color: Color(0xFF22C55E)),
  Category(id: 'health',      name: 'Health',         icon: Icons.favorite,         color: Color(0xFFFF6B9D)),
  Category(id: 'bills',       name: 'Bills',          icon: Icons.receipt_long,     color: Color(0xFF6C63FF)),
  Category(id: 'entertainment',name: 'Entertainment', icon: Icons.movie,            color: Color(0xFFFF9F43)),
  Category(id: 'other',       name: 'Other',          icon: Icons.more_horiz,       color: Color(0xFF9E9EBE)),
];

Category categoryById(String id) =>
    kCategories.firstWhere((c) => c.id == id,
        orElse: () => kCategories.last);