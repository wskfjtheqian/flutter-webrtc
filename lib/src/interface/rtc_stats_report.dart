class StatsReport {
  StatsReport(this.id, this.type, this.timestamp, this.values);

  factory StatsReport.fromMap(Map<String, dynamic> map) => StatsReport(map['id'], map['type'], map['timestamp'], map);
  final String id;
  final String type;
  final double timestamp;
  final Map<dynamic, dynamic> values;

  @override
  String toString() {
    return 'StatsReport{id: $id, type: $type, timestamp: $timestamp, values: $values}';
  }
}
