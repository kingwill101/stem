import 'package:flutter/material.dart';
import 'package:stem/stem.dart';

import 'demos/workflow_error_card.dart';
import 'greeting_workflow.dart';

/// One screen: type a name, tap the button, await the workflow, show it.
///
/// The button submits [greetingWorkflow] with the text field as input and
/// awaits `run.result` on the current screen. `Isolate.run` inside the
/// workflow keeps the UI responsive while the greeting is computed off the
/// UI isolate.
///
/// Without [createHost] the page owns its host (created once, closed on
/// dispose). With [createHost] the host is borrowed and the caller owns
/// teardown — this also keeps widget tests in control of async shutdown.
class GreetingPage extends StatefulWidget {
  const GreetingPage({super.key, this.createHost});

  final Future<WorkflowHost> Function()? createHost;

  @override
  State<GreetingPage> createState() => _GreetingPageState();
}

class _GreetingPageState extends State<GreetingPage> {
  WorkflowHost? _host;
  var _ownsHost = false;
  String? _hostError;
  final _name = TextEditingController(text: 'Ada');
  bool _running = false;
  String? _result;
  Object? _runError;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final borrowed = widget.createHost != null;
      final host = borrowed
          ? await widget.createHost!()
          : await WorkflowHost.inMemory(workflows: [greetingWorkflow]);
      _ownsHost = !borrowed;
      if (!mounted) {
        await host.close();
        return;
      }
      setState(() => _host = host);
    } catch (error) {
      if (!mounted) return;
      setState(() => _hostError = '$error');
    }
  }

  Future<void> _runGreeting() async {
    final host = _host;
    if (host == null || _running) return;
    setState(() {
      _running = true;
      _result = null;
      _runError = null;
    });
    try {
      final run = await host.submit(greetingWorkflow, _name.text);
      final result = await run.result;
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _runError = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    // State.dispose is sync, so an owned host closes fire-and-forget here.
    // A borrowed host (via createHost) is left for its owner to close.
    final host = _ownsHost ? _host : null;
    _host = null;
    _ownsHost = false;
    if (host != null) {
      // ignore: discarded_futures
      host.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hostError = _hostError;
    final host = _host;
    return Scaffold(
      appBar: AppBar(title: const Text('Workflow button demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              enabled: !_running,
              onSubmitted: (_) => _runGreeting(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: host == null || _running ? null : _runGreeting,
              child: Text(_running ? 'Running…' : 'Greet me'),
            ),
            const SizedBox(height: 16),
            if (hostError != null)
              Text('Host failed to start: $hostError')
            else if (host == null)
              const Center(child: CircularProgressIndicator())
            else if (_running)
              const Center(child: CircularProgressIndicator())
            else if (_runError != null)
              WorkflowErrorCard(title: 'Workflow failed.', error: _runError!)
            else if (_result != null)
              Text(_result!, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
