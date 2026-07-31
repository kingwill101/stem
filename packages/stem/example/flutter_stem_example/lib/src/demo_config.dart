const String queueName = 'mobile-demo';
const String taskName = 'demo.sleep_echo';
const String workerId = 'mobile-worker';

const Duration workerHeartbeatInterval = Duration(seconds: 2);
const Duration monitorPollInterval = Duration(seconds: 1);
const Duration brokerPollInterval = Duration(milliseconds: 250);
const Duration brokerSweepInterval = Duration(seconds: 2);
const Duration brokerVisibilityTimeout = Duration(seconds: 6);
const Duration producerMaintenanceInterval = Duration.zero;
const Duration monitorCleanupInterval = Duration(days: 3650);
