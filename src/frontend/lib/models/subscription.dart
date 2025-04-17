class Subscription {
  final String resource;
  final String? id;
  
  const Subscription(this.resource, {this.id});
  
  @override
  String toString() => id != null ? '$resource:$id' : resource;
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Subscription && 
           other.resource == resource && 
           other.id == id;
  }
  
  @override
  int get hashCode => resource.hashCode ^ (id?.hashCode ?? 0);
}
