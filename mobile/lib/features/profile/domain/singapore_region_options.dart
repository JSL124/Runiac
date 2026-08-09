import '../../../core/regions/singapore_planning_area_catalog.dart';

class SingaporeRegionOptions {
  const SingaporeRegionOptions._();

  static final values = List<String>.unmodifiable(
    supportedSingaporePlanningAreas.map((area) => area.locationLabel),
  );

  static bool contains(String value) =>
      singaporePlanningAreaForLocationLabel(value) != null;
}
