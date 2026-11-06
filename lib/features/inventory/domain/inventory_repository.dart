class StockPosition {
  const StockPosition(
    this.productId,
    this.name,
    this.unit,
    this.quantity,
    this.version,
  );
  final String productId, name, unit, quantity;
  final int version;
}

class StockOutlet {
  const StockOutlet(this.id, this.name);
  final String id, name;
}

class StockMovement {
  const StockMovement(this.quantity, this.reason, this.createdAt);
  final String quantity, reason, createdAt;
}

abstract interface class InventoryRepository {
  Future<List<StockOutlet>> outlets(String organizationId);
  Future<List<StockPosition>> positions(
    String organizationId,
    String outletId,
    int offset, {
    bool lowOnly = false,
  });
  Future<List<StockMovement>> movements(
    String organizationId,
    String outletId,
    String productId,
    int offset,
  );
  Future<void> count(
    String requestId,
    String organizationId,
    String outletId,
    StockPosition position,
    String quantity,
    String reason,
  );
}
