import 'package:flutter/material.dart';

import '../cart/cart_page.dart';
import '../greeting_page.dart';

/// Entry point for the Stem workflow demos.
///
/// Each card pushes a self-contained demo: the greeter shows a button
/// submitting a workflow and awaiting its isolate-computed result, while the
/// mini-Medusa cart shows multi-step checkout with compensation and a
/// reusable fulfillment workflow.
class DemosLandingPage extends StatelessWidget {
  const DemosLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stem workflow demos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DemoCard(
            title: 'Greeter',
            description:
                'Type a name, tap the button, and await a workflow result '
                'computed off the UI isolate.',
            buttonLabel: 'Open greeter demo',
            onOpen: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const GreetingPage())),
          ),
          const SizedBox(height: 12),
          _DemoCard(
            title: 'Mini Medusa: cart checkout',
            description:
                'A Medusa-style commerce flow: validate, reserve, charge, '
                'and fulfill, with rollback on failure and a fulfillment '
                'workflow that also runs on its own.',
            buttonLabel: 'Open cart demo',
            onOpen: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const CartPage())),
          ),
        ],
      ),
    );
  }
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onOpen,
  });

  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 12),
            FilledButton(onPressed: onOpen, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}
