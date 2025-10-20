class ReceiptInfo {
  ReceiptInfo({
    required this.stream,
    required this.group,
    required this.consumer,
    required this.id,
  });

  final String stream;
  final String group;
  final String consumer;
  final String id;
}
