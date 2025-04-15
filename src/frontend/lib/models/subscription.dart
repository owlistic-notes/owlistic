class Subscription {
  final String resource;
  final String? id;
  
  const Subscription(this.resource, {this.id});
  
  @override
  String toString() => id != null ? '$resource:$id' : resource;
}
