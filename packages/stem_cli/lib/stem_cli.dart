/// Command-line entrypoints and routing helpers for Stem worker processes.
///
/// This library exposes the top-level APIs used to bootstrap the Stem CLI,
/// build worker subscriptions from routing configuration, and create the
/// default command context used by command-line hosts.
library stem_cli;

export 'src/cli/cli_runner.dart' show CliContext, runStemCli;
export 'src/cli/subscription_loader.dart'
    show
        RoutingConfigLoader,
        StemRoutingContext,
        WorkerSubscriptionBuilder,
        buildWorkerSubscription;
export 'src/cli/utilities.dart' show createDefaultContext;
