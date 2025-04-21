class Subscription {
  final String resource;
  final String? id;
  
  Subscription(this.resource, {this.id});
  
  @override
  String toString() => 'Subscription{resource: $resource, id: $id}';
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Subscription &&
          runtimeType == other.runtimeType &&
          resource == other.resource &&
          id == other.id;

  @override
  int get hashCode => resource.hashCode ^ (id?.hashCode ?? 0);
}
