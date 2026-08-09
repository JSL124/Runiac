// GENERATED FILE. Run: node tools/leaderboard/generate_leaderboard_contracts.mjs
//
// The Singapore planning areas the regional leaderboard ranks within, and the
// region each one rolls up to. Do not edit by hand — the same generator emits
// the backend's copy, and the two must agree or a runner can be scored into a
// region the server does not recognise.
class SingaporePlanningArea {
  const SingaporePlanningArea({
    required this.regionId,
    required this.regionName,
    required this.locationLabel,
    required this.planningAreaName,
    required this.planningAreaCode,
    required this.planningRegionCode,
  });

  final String regionId;
  final String regionName;
  final String locationLabel;
  final String planningAreaName;
  final String planningAreaCode;
  final String planningRegionCode;
}

const supportedSingaporePlanningAreas = <SingaporePlanningArea>[
  SingaporePlanningArea(
    regionId: 'jurong-east',
    regionName: 'Jurong East',
    locationLabel: 'Jurong East, Singapore',
    planningAreaName: 'JURONG EAST',
    planningAreaCode: 'JE',
    planningRegionCode: 'WR',
  ),
  SingaporePlanningArea(
    regionId: 'orchard',
    regionName: 'Orchard',
    locationLabel: 'Orchard, Singapore',
    planningAreaName: 'ORCHARD',
    planningAreaCode: 'OR',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'ang-mo-kio',
    regionName: 'Ang Mo Kio',
    locationLabel: 'Ang Mo Kio, Singapore',
    planningAreaName: 'ANG MO KIO',
    planningAreaCode: 'AM',
    planningRegionCode: 'NER',
  ),
  SingaporePlanningArea(
    regionId: 'bedok',
    regionName: 'Bedok',
    locationLabel: 'Bedok, Singapore',
    planningAreaName: 'BEDOK',
    planningAreaCode: 'BD',
    planningRegionCode: 'ER',
  ),
  SingaporePlanningArea(
    regionId: 'bishan',
    regionName: 'Bishan',
    locationLabel: 'Bishan, Singapore',
    planningAreaName: 'BISHAN',
    planningAreaCode: 'BS',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'boon-lay',
    regionName: 'Boon Lay',
    locationLabel: 'Boon Lay, Singapore',
    planningAreaName: 'BOON LAY',
    planningAreaCode: 'BL',
    planningRegionCode: 'WR',
  ),
  SingaporePlanningArea(
    regionId: 'bukit-batok',
    regionName: 'Bukit Batok',
    locationLabel: 'Bukit Batok, Singapore',
    planningAreaName: 'BUKIT BATOK',
    planningAreaCode: 'BK',
    planningRegionCode: 'WR',
  ),
  SingaporePlanningArea(
    regionId: 'bukit-merah',
    regionName: 'Bukit Merah',
    locationLabel: 'Bukit Merah, Singapore',
    planningAreaName: 'BUKIT MERAH',
    planningAreaCode: 'BM',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'bukit-panjang',
    regionName: 'Bukit Panjang',
    locationLabel: 'Bukit Panjang, Singapore',
    planningAreaName: 'BUKIT PANJANG',
    planningAreaCode: 'BP',
    planningRegionCode: 'WR',
  ),
  SingaporePlanningArea(
    regionId: 'bukit-timah',
    regionName: 'Bukit Timah',
    locationLabel: 'Bukit Timah, Singapore',
    planningAreaName: 'BUKIT TIMAH',
    planningAreaCode: 'BT',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'changi',
    regionName: 'Changi',
    locationLabel: 'Changi, Singapore',
    planningAreaName: 'CHANGI',
    planningAreaCode: 'CH',
    planningRegionCode: 'ER',
  ),
  SingaporePlanningArea(
    regionId: 'choa-chu-kang',
    regionName: 'Choa Chu Kang',
    locationLabel: 'Choa Chu Kang, Singapore',
    planningAreaName: 'CHOA CHU KANG',
    planningAreaCode: 'CK',
    planningRegionCode: 'WR',
  ),
  SingaporePlanningArea(
    regionId: 'clementi',
    regionName: 'Clementi',
    locationLabel: 'Clementi, Singapore',
    planningAreaName: 'CLEMENTI',
    planningAreaCode: 'CL',
    planningRegionCode: 'WR',
  ),
  SingaporePlanningArea(
    regionId: 'downtown-core',
    regionName: 'Downtown Core',
    locationLabel: 'Downtown Core, Singapore',
    planningAreaName: 'DOWNTOWN CORE',
    planningAreaCode: 'DT',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'geylang',
    regionName: 'Geylang',
    locationLabel: 'Geylang, Singapore',
    planningAreaName: 'GEYLANG',
    planningAreaCode: 'GL',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'hougang',
    regionName: 'Hougang',
    locationLabel: 'Hougang, Singapore',
    planningAreaName: 'HOUGANG',
    planningAreaCode: 'HG',
    planningRegionCode: 'NER',
  ),
  SingaporePlanningArea(
    regionId: 'jurong-west',
    regionName: 'Jurong West',
    locationLabel: 'Jurong West, Singapore',
    planningAreaName: 'JURONG WEST',
    planningAreaCode: 'JW',
    planningRegionCode: 'WR',
  ),
  SingaporePlanningArea(
    regionId: 'kallang',
    regionName: 'Kallang',
    locationLabel: 'Kallang, Singapore',
    planningAreaName: 'KALLANG',
    planningAreaCode: 'KL',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'marine-parade',
    regionName: 'Marine Parade',
    locationLabel: 'Marine Parade, Singapore',
    planningAreaName: 'MARINE PARADE',
    planningAreaCode: 'MP',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'museum',
    regionName: 'Museum',
    locationLabel: 'Museum, Singapore',
    planningAreaName: 'MUSEUM',
    planningAreaCode: 'MU',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'newton',
    regionName: 'Newton',
    locationLabel: 'Newton, Singapore',
    planningAreaName: 'NEWTON',
    planningAreaCode: 'NT',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'novena',
    regionName: 'Novena',
    locationLabel: 'Novena, Singapore',
    planningAreaName: 'NOVENA',
    planningAreaCode: 'NV',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'outram',
    regionName: 'Outram',
    locationLabel: 'Outram, Singapore',
    planningAreaName: 'OUTRAM',
    planningAreaCode: 'OT',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'pasir-ris',
    regionName: 'Pasir Ris',
    locationLabel: 'Pasir Ris, Singapore',
    planningAreaName: 'PASIR RIS',
    planningAreaCode: 'PR',
    planningRegionCode: 'ER',
  ),
  SingaporePlanningArea(
    regionId: 'punggol',
    regionName: 'Punggol',
    locationLabel: 'Punggol, Singapore',
    planningAreaName: 'PUNGGOL',
    planningAreaCode: 'PG',
    planningRegionCode: 'NER',
  ),
  SingaporePlanningArea(
    regionId: 'queenstown',
    regionName: 'Queenstown',
    locationLabel: 'Queenstown, Singapore',
    planningAreaName: 'QUEENSTOWN',
    planningAreaCode: 'QT',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'river-valley',
    regionName: 'River Valley',
    locationLabel: 'River Valley, Singapore',
    planningAreaName: 'RIVER VALLEY',
    planningAreaCode: 'RV',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'rochor',
    regionName: 'Rochor',
    locationLabel: 'Rochor, Singapore',
    planningAreaName: 'ROCHOR',
    planningAreaCode: 'RC',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'sembawang',
    regionName: 'Sembawang',
    locationLabel: 'Sembawang, Singapore',
    planningAreaName: 'SEMBAWANG',
    planningAreaCode: 'SB',
    planningRegionCode: 'NR',
  ),
  SingaporePlanningArea(
    regionId: 'sengkang',
    regionName: 'Sengkang',
    locationLabel: 'Sengkang, Singapore',
    planningAreaName: 'SENGKANG',
    planningAreaCode: 'SE',
    planningRegionCode: 'NER',
  ),
  SingaporePlanningArea(
    regionId: 'serangoon',
    regionName: 'Serangoon',
    locationLabel: 'Serangoon, Singapore',
    planningAreaName: 'SERANGOON',
    planningAreaCode: 'SG',
    planningRegionCode: 'NER',
  ),
  SingaporePlanningArea(
    regionId: 'singapore-river',
    regionName: 'Singapore River',
    locationLabel: 'Singapore River, Singapore',
    planningAreaName: 'SINGAPORE RIVER',
    planningAreaCode: 'SR',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'tampines',
    regionName: 'Tampines',
    locationLabel: 'Tampines, Singapore',
    planningAreaName: 'TAMPINES',
    planningAreaCode: 'TM',
    planningRegionCode: 'ER',
  ),
  SingaporePlanningArea(
    regionId: 'tanglin',
    regionName: 'Tanglin',
    locationLabel: 'Tanglin, Singapore',
    planningAreaName: 'TANGLIN',
    planningAreaCode: 'TN',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'toa-payoh',
    regionName: 'Toa Payoh',
    locationLabel: 'Toa Payoh, Singapore',
    planningAreaName: 'TOA PAYOH',
    planningAreaCode: 'TP',
    planningRegionCode: 'CR',
  ),
  SingaporePlanningArea(
    regionId: 'woodlands',
    regionName: 'Woodlands',
    locationLabel: 'Woodlands, Singapore',
    planningAreaName: 'WOODLANDS',
    planningAreaCode: 'WD',
    planningRegionCode: 'NR',
  ),
  SingaporePlanningArea(
    regionId: 'yishun',
    regionName: 'Yishun',
    locationLabel: 'Yishun, Singapore',
    planningAreaName: 'YISHUN',
    planningAreaCode: 'YS',
    planningRegionCode: 'NR',
  ),
];

const _planningAreaAliases = <String, String>{
  'central area, singapore': 'downtown core, singapore',
  'tiong bahru, singapore': 'bukit merah, singapore',
};

SingaporePlanningArea? singaporePlanningAreaForLocationLabel(String value) {
  final normalized = value.trim().toLowerCase();
  final target = _planningAreaAliases[normalized] ?? normalized;
  for (final area in supportedSingaporePlanningAreas) {
    if (area.locationLabel.toLowerCase() == target) {
      return area;
    }
  }
  return null;
}

SingaporePlanningArea? singaporePlanningAreaForRegionId(String value) {
  final normalized = value.trim();
  for (final area in supportedSingaporePlanningAreas) {
    if (area.regionId == normalized) {
      return area;
    }
  }
  return null;
}
