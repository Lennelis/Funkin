import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/app_state.dart';
import 'theme/funkin_theme.dart';
import 'ui/hub_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // The editors are drawn dark and edge to edge; the system bars sit over them
  // rather than boxing them in.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: FunkinColors.panel,
  ));

  runApp(const FunkinEditorsApp());
}

class FunkinEditorsApp extends StatelessWidget {
  const FunkinEditorsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AppState()..restore(),
      child: MaterialApp(
        title: 'Funkin Editors',
        debugShowCheckedModeBanner: false,
        theme: buildFunkinTheme(),
        home: const HubPage(),
      ),
    );
  }
}
