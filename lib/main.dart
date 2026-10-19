import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/app/router.dart';
import 'package:tapsense/app/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://wtyyodplhdvzjrnwqeuk.supabase.co',
    anonKey: 'sb_publishable_cxI7J6h-L95tyj3wtHnouw_dpkt3n4B',
  );
  runApp(const TapSenseApp());
}

class TapSenseApp extends StatelessWidget {
  const TapSenseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TapSense',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: appRouter,
    );
  }
}