"""
Temporary live API tests for debugging POI discovery
WARNING: These hit the real Mapbox API - use sparingly!
"""

import pytest
import requests
import json
from app.utils.polyline import decode_polyline, calculate_bounds

BASE_URL = "http://localhost:8000"


def test_polyline_decoder():
    """Test that polyline decoder produces valid coordinates"""
    # Simple test polyline (SF to LA area) - encoded with precision 5
    test_polyline = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"

    points = decode_polyline(test_polyline, precision=5)

    print(f"\n✅ Decoded {len(points)} points")
    print(f"First point: {points[0]}")
    print(f"Last point: {points[-1]}")

    # Check all coordinates are valid
    for i, (lat, lng) in enumerate(points):
        assert -90 <= lat <= 90, f"Invalid latitude at point {i}: {lat}"
        assert -180 <= lng <= 180, f"Invalid longitude at point {i}: {lng}"
        print(f"Point {i}: lat={lat:.6f}, lng={lng:.6f} ✓")

    assert len(points) > 0
    print("\n✅ All coordinates valid!")


def test_poi_endpoint_with_test_polyline():
    """Test POI endpoint with known good polyline"""
    payload = {
        "encoded_polyline": "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
        "categories": ["restaurant"],
        "corridor_radius_miles": 5.0,
        "limit_per_category": 3
    }

    print(f"\n📤 Sending request to {BASE_URL}/api/v1/route/pois")
    print(f"Payload: {json.dumps(payload, indent=2)}")

    response = requests.post(
        f"{BASE_URL}/api/v1/route/pois",
        json=payload,
        timeout=15
    )

    print(f"\n📥 Response status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")

    assert response.status_code == 200
    data = response.json()

    print(f"\n✅ Found {data['total_found']} POIs")
    print(f"Cached: {data['cached']}")
    print(f"Bounds: {data['corridor_bounds']}")

    for poi in data['pois']:
        print(f"\n  📍 {poi['name']}")
        print(f"     Category: {poi['category']}")
        print(f"     Location: {poi['latitude']:.6f}, {poi['longitude']:.6f}")
        print(f"     Distance: {poi['distance_from_route_miles']:.2f} miles")


def test_poi_endpoint_with_real_route():
    """
    Test with a REAL route polyline from the app

    TODO: Replace this with the actual polyline from your app!
    You can get it from the backend logs when you click "Discover POIs"
    """
    # San Francisco to Los Angeles (approximate route)
    sf_to_la_polyline = "ypqeFxzfjVnC~CrBxBtA|@v@\\^JVBx@TfAj@~@x@t@~@f@`At@dBh@nBn@jCl@xCTbBRjBNxBD|@?p@Cd@Ek@Kw@]aCy@mHSyBK_BC_A@q@@s@DqALkBTyBj@_Fx@iHZoD^}DXcDVqDJqCDoBBwB?qBCqBGqBMoBQqBWoBa@oBi@mBs@kB}@gBeAcBmAaB{@aAyAeByAmBiAaB_@i@k@w@u@cAs@{@aAiAiAmAwAkAcAy@mAaAcAs@oAaAw@q@uAgAsAsA_B{AoBoBsCyCaC_CoBwAkAy@iA}@uAiAoAmA{@iAmAyAgAeB}@}AoAmBgAoB_AgBs@_BaAoBq@aBk@aBa@mAYaAYaA_@qAc@yAe@}A_@qAa@}Ak@eBq@{B]qA]kAYaAc@wAm@yBq@eBk@aBc@iAo@eBq@sBg@eBk@_Cm@qBi@kBg@{Au@}Bq@yBi@eBu@kCu@iCe@eBo@wBm@wBw@gCw@gC{@mCy@gCaAeDkAqD}@oCu@}Bs@}BcAeDkAoDuAmEmAsD{AqEkAiD_AmC}@gCaA_DoAcEaAqCcAeDoAqD}@iC_AcD}@qCaAyD{@wC}@qDaAyD_A}D{@_Ey@gEw@kEaAsGq@oE}@oGaAoGaAiH}@qF{@yFy@aGq@cGm@cGk@aGi@cGg@iGc@kG_@kG[kGWmGSmGOmGKoGGmGCqG?qG@oGDoGHoGNmGRmGVkG\\kGb@iGf@gGl@eGr@cGx@aG~@_GfA{FnAyFtAwFlA}EvAyEzAwE`BqEdBmEhBiElByDrBsDvBkDzBgD~BaD`C}CdCyCjCsCnCmCrCiCvC}BxCwB|CqB`DiCdCmCxBqC|BeCdCuB|B_CjCgBxBsB|BuB`CqBbCoBfCkBfCeBhC_BjCwAlC_BlCmAtCcAnCsAtC_BnC}A`D{ApC}A`DkA~CeAnDoAvCy@lCy@jCw@fCu@bC}@pCq@bCk@~Bi@~Bi@xBg@tBe@pBc@jBi@dBm@fBk@hBi@dBk@`Bo@`Bu@~Aw@~A{@zAaA|A}@xA{@xA_AtA}@tA{@rA_AnA}@nAaAlAcAjAeAhAiA~@mA|@qAz@sAv@uAt@yAp@{An@}Al@_Bh@eBd@eBb@iB\\kBZmBVoBToB\\aBj@wB~@mDt@gCh@_Bf@cBn@_Bp@aBr@cBv@_Bz@aBbAgB`AqA`AmArAeBbByBjAwApAgBnAsA|AeBpAaBlAaB~@eAbAoAbAsAfAyAnAmAvAsAlAyAnAgAtAwAdAwAl@_Ap@eAtAmApAcAhAeArA_AlA}@jAsAnAqAvAuAzAuArAeAz@aAnAaA`BkAbBcApAo@nAw@nAw@hAu@hAs@jAs@jAs@hAq@hAq@jAo@lAm@jAk@lAi@lAi@nAg@nAg@pAe@pAc@rAa@tA_@tA]vA[xAYxAWzAUzAS|AQ|AO~AM`BC~A?dA@dADdAFdAH`BJbANdA\\jAj@zA`@fAt@nBp@dBjAvCn@vAtApCbAjBn@tAjAtBfA|BjAvBdBxCnBlDrBdD~AzCdBzCrAbCfArBjA~BbApBl@pA`@|@d@fAh@jAf@hAh@jAj@hAl@jAn@fAr@fAt@fAv@dAz@dA|@bA`AbAhA`AlA~@nA|@pAz@rAx@tAv@vAt@xAr@|Ap@~An@bBn@dBl@fBj@jBj@lBh@pBf@tBf@vBd@zBb@bCb@fC`@jC^nC\\pCZvCXzCVbDTfDRlDPpDNvDLzDJ~DH`EDfE?jECtEGvEKvEMtEQrEUrEYnE]jEa@hEe@dEi@`Em@|Dq@xDu@tDy@pD}@lDaAhDeA`DgA|CkAvCkArCmAnCoAjCsAfCsAhCsAhCqAjCgAnC_@`A_@`A_@~@a@~@_@~@a@|@c@|@c@z@e@z@g@x@k@v@m@t@o@r@q@p@s@n@w@l@{@j@}@h@cAf@gAb@iA`@mA\\qAXuATyAP}AL_BHeAD_A@i@?q@As@Cw@Es@I}@Ms@Qu@Sy@[s@]q@a@m@e@k@i@i@k@e@o@c@s@_@w@[{@W}@S}@OaAKaAGeACiA?iA@iADgAHgALgAP}@T}@X{@\\y@b@u@f@q@j@q@n@k@r@i@v@e@z@a@~@]bA[fAWjASfAOnAKhAGhACn@@jADfAHfALdAPdAT`AX|@\\x@`@t@d@p@h@l@l@h@p@d@t@`@x@\\|@X`AThAP"

    # Decode it first to verify
    points = decode_polyline(sf_to_la_polyline)
    print(f"\n📏 Route has {len(points)} points")
    print(f"   First: {points[0]}")
    print(f"   Middle: {points[len(points)//2]}")
    print(f"   Last: {points[-1]}")

    # Verify all coordinates are valid
    for i, (lat, lng) in enumerate(points[:5]):  # Check first 5
        print(f"   Point {i}: lat={lat:.6f}, lng={lng:.6f}")
        assert -90 <= lat <= 90, f"Invalid lat: {lat}"
        assert -180 <= lng <= 180, f"Invalid lng: {lng}"

    payload = {
        "encoded_polyline": sf_to_la_polyline,
        "categories": ["gas_station", "restaurant"],
        "corridor_radius_miles": 5.0,
        "limit_per_category": 5
    }

    print(f"\n📤 Sending real route to API...")

    response = requests.post(
        f"{BASE_URL}/api/v1/route/pois",
        json=payload,
        timeout=20
    )

    print(f"📥 Response status: {response.status_code}")

    if response.status_code != 200:
        print(f"❌ Error: {response.text}")

    assert response.status_code == 200
    data = response.json()

    print(f"\n✅ SUCCESS! Found {data['total_found']} POIs")
    print(f"   Cached: {data['cached']}")
    print(f"   Bounds: {data['corridor_bounds']}")

    for poi in data['pois'][:5]:  # Show first 5
        print(f"\n  📍 {poi['name']}")
        print(f"     {poi['category']} - {poi['distance_from_route_miles']:.1f} mi")


if __name__ == "__main__":
    print("=" * 70)
    print("🧪 POI Discovery Live API Tests")
    print("=" * 70)

    print("\n" + "=" * 70)
    print("TEST 1: Polyline Decoder")
    print("=" * 70)
    test_polyline_decoder()

    print("\n" + "=" * 70)
    print("TEST 2: POI Endpoint with Test Polyline")
    print("=" * 70)
    test_poi_endpoint_with_test_polyline()

    print("\n" + "=" * 70)
    print("TEST 3: POI Endpoint with Real SF→LA Route")
    print("=" * 70)
    test_poi_endpoint_with_real_route()

    print("\n" + "=" * 70)
    print("✅ ALL TESTS PASSED!")
    print("=" * 70)
