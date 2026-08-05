import 'package:flutter/material.dart' show Color;
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Real campus boundary polygons extracted from the official KML exports:
///   Bloemfontein_Campus.kml — 6 named sub-areas
///   Welkom_Campus.kml       — 1 polygon
///
/// Coordinates were parsed directly from each <Polygon><outerBoundaryIs>
/// <LinearRing><coordinates> block (lon,lat,alt → converted to LatLng(lat,lon)).
class CampusBoundary {
  CampusBoundary._();

  // ── Bloemfontein Campus — 6 sub-area polygons ─────────────────

  static const List<LatLng> bfnMainCampus = [
    LatLng(-29.1195274, 26.2128742),
    LatLng(-29.1210458, 26.2123592),
    LatLng(-29.1211863, 26.2124235),
    LatLng(-29.1214019, 26.2130351),
    LatLng(-29.1225641, 26.2126381),
    LatLng(-29.1224235, 26.2119729),
    LatLng(-29.1236045, 26.211576),
    LatLng(-29.1238294, 26.2117905),
    LatLng(-29.1244386, 26.2148054),
    LatLng(-29.1220674, 26.2154598),
    LatLng(-29.121908, 26.2154062),
    LatLng(-29.1201741, 26.2158246),
    LatLng(-29.1197617, 26.2137968),
    LatLng(-29.1197898, 26.2136145),
    LatLng(-29.1195274, 26.2128742),
  ];

  static const List<LatLng> bfnFebit = [
    LatLng(-29.122214, 26.2179489),
    LatLng(-29.1219515, 26.2167044),
    LatLng(-29.1213048, 26.216876),
    LatLng(-29.1211455, 26.2171657),
    LatLng(-29.1204894, 26.2172837),
    LatLng(-29.120227, 26.2159426),
    LatLng(-29.1218016, 26.2155671),
    LatLng(-29.1222515, 26.2155564),
    LatLng(-29.1223921, 26.2157066),
    LatLng(-29.1228326, 26.2177558),
    LatLng(-29.122214, 26.2179489),
  ];

  static const List<LatLng> bfnSportsGrounds = [
    LatLng(-29.122467, 26.2155135),
    LatLng(-29.1247633, 26.2148697),
    LatLng(-29.125007, 26.2149126),
    LatLng(-29.1253444, 26.2162752),
    LatLng(-29.1245758, 26.2166078),
    LatLng(-29.1240416, 26.217155),
    LatLng(-29.1243696, 26.2171979),
    LatLng(-29.1245008, 26.2174232),
    LatLng(-29.1247633, 26.2186034),
    LatLng(-29.1246602, 26.2188179),
    LatLng(-29.1237511, 26.2190003),
    LatLng(-29.1234136, 26.217627),
    LatLng(-29.1229638, 26.2177451),
    LatLng(-29.122467, 26.2155135),
  ];

  static const List<LatLng> bfnLoggiesResidence = [
    LatLng(-29.1223358, 26.2180347),
    LatLng(-29.1233855, 26.2177558),
    LatLng(-29.1235167, 26.2184317),
    LatLng(-29.1224764, 26.2187106),
    LatLng(-29.1223358, 26.2180347),
  ];

  static const List<LatLng> bfnMennheim = [
    LatLng(-29.1223592, 26.2075285),
    LatLng(-29.1218133, 26.2076787),
    LatLng(-29.1215743, 26.2065897),
    LatLng(-29.1219422, 26.2064932),
    LatLng(-29.1219117, 26.2063215),
    LatLng(-29.1220921, 26.2062652),
    LatLng(-29.1223592, 26.2075285),
  ];

  static const List<LatLng> bfnGmynosResidence = [
    LatLng(-29.1208523, 26.209808),
    LatLng(-29.1214134, 26.2096524),
    LatLng(-29.1214767, 26.2099783),
    LatLng(-29.1209202, 26.2101245),
    LatLng(-29.1208523, 26.209808),
  ];

  // ── Welkom Campus — single polygon ─────────────────────────────

  static const List<LatLng> welkomCampus = [
    LatLng(-27.9515834, 26.7838441),
    LatLng(-27.9503798, 26.786301),
    LatLng(-27.949432, 26.7857431),
    LatLng(-27.9460296, 26.7870627),
    LatLng(-27.9448828, 26.7832432),
    LatLng(-27.9488729, 26.781591),
    LatLng(-27.9491003, 26.7820845),
    LatLng(-27.9515834, 26.7838441),
  ];

  /// All Bloemfontein sub-area polygons rendered as Google Map Polygons.
  static Set<Polygon> bloemfonteinPolygons() {
    const grey = Color(0x26757575);
    const fillBg = Color(0x336e757575); // ~43% alpha of poly-757575 style

    Polygon poly(String id, List<LatLng> points) => Polygon(
          polygonId: PolygonId(id),
          points: points,
          strokeWidth: 2,
          strokeColor: grey,
          fillColor: fillBg,
          geodesic: true,
        );

    return {
      poly('bfn_main_campus', bfnMainCampus),
      poly('bfn_febit', bfnFebit),
      poly('bfn_sports_grounds', bfnSportsGrounds),
      poly('bfn_loggies_res', bfnLoggiesResidence),
      poly('bfn_mennheim', bfnMennheim),
      poly('bfn_gmynos_res', bfnGmynosResidence),
    };
  }

  /// Welkom campus polygon.
  static Set<Polygon> welkomPolygons() {
    const grey = Color(0xFF757575);
    const fillBg = Color(0x336e757575);

    return {
      const Polygon(
        polygonId: PolygonId('welkom_campus'),
        points: welkomCampus,
        strokeWidth: 2,
        strokeColor: grey,
        fillColor: fillBg,
        geodesic: true,
      ),
    };
  }

  /// Combined set — both campuses' boundaries together.
  static Set<Polygon> allPolygons() => {
        ...bloemfonteinPolygons(),
        ...welkomPolygons(),
      };

  /// Sub-area labels for an optional legend / info popup.
  static const Map<String, String> bfnAreaLabels = {
    'bfn_main_campus': 'Main Campus',
    'bfn_febit': 'FEBIT',
    'bfn_sports_grounds': 'Sports Grounds',
    'bfn_loggies_res': 'Loggies Residence',
    'bfn_mennheim': 'Mennheim Men & Ladies',
    'bfn_gmynos_res': 'Gmynos Residence',
  };
}
