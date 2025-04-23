/// Represents a WebSocket subscription to a resource
class Subscription {
  /// The resource type (e.g., "note", "block", "notebook")
  final String resource;
  
  /// Optional ID for the specific resource instance
  final String? id;
  
  /// Create a new subscription
  Subscription({
    required this.resource,
    this.id,
  });
  
  /// Create a subscription from a string key (format: "resource:id" or just "resource")
  factory Subscription.fromKey(String key) {
    final parts = key.split(':');
    if (parts.length > 1) {
      return Subscription(
        resource: parts[0],
        id: parts[1],
      );
    } else {
      return Subscription(resource: key);
    }
  }
  
  /// Convert to a string key format
  String toKey() {
    return id != null && id!.isNotEmpty ? '$resource:$id' : resource;
  }
  
  @override
  String toString() {
    return id != null ? 'Subscription($resource:$id)' : 'Subscription($resource)';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Subscription) return false;
    return resource == other.resource && id == other.id;
  }
  
  @override
  int get hashCode => resource.hashCode ^ (id?.hashCode ?? 0);
}
