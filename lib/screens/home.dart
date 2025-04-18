import 'package:fluent_ui/fluent_ui.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage.scrollable(
      header: const PageHeader(
        title: Text('Hello, world'),
      ),
      children: const [
        Center(
          child: Text(
            'Hello, world',
            style: TextStyle(fontSize: 24),
          ),
        ),
      ],
    );
  }
}
