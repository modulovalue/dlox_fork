abstract class DloxDataset {
  String get name;

  Z match<Z>({
    required final Z Function(DloxDatasetInternal) internal,
    required final Z Function(DloxDatasetLeaf) leaf,
  });
}

mixin DloxDatasetInternal implements DloxDataset {
  @override
  String get name;

  List<DloxDataset> get children;

  @override
  Z match<Z>({
    required final Z Function(DloxDatasetInternal) internal,
    required final Z Function(DloxDatasetLeaf) leaf,
  }) {
    return internal(this);
  }
}

mixin DloxDatasetLeaf implements DloxDataset {
  @override
  String get name;

  String get source;

  @override
  Z match<Z>({
    required final Z Function(DloxDatasetInternal) internal,
    required final Z Function(DloxDatasetLeaf) leaf,
  }) {
    return leaf(this);
  }
}

class DloxDatasetLeafImpl with DloxDatasetLeaf {
  @override
  final String name;
  @override
  final String source;

  const DloxDatasetLeafImpl({
    required final this.name,
    required final this.source,
  });

  @override
  Z match<Z>({
    required final Z Function(DloxDatasetInternal) internal,
    required final Z Function(DloxDatasetLeaf) leaf,
  }) {
    return leaf(this);
  }
}
