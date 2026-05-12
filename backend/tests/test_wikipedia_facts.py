"""Tests for the Wikipedia GeoSearch fact source.

The contract this file pins:
  - polyline → list of sample points at trip-scale-aware strides
  - sample points → parallel geosearch → deduped pageid set
  - pageids → parallel extract fetch → FactCandidate list

Real Wikipedia is not contacted. We feed a stubbed httpx.AsyncClient
canned responses keyed off the request URL/params so the parsing
contract is exercised without flaky network.
"""

import asyncio
import json
from typing import Optional
from unittest.mock import patch

import httpx
import pytest

from app.services.wikipedia_facts import (
    FactCandidate,
    WikipediaFactsService,
    _stride_sample,
    _min_distance_to_route,
)
from app.utils.polyline import calculate_distance_miles


def test_stride_sample_includes_endpoints():
    # Two-point polyline, stride larger than the route length →
    # we still get both endpoints, because callers depend on the
    # start of the route always being geosearched.
    coords = [(37.7749, -122.4194), (37.7849, -122.4094)]  # ~0.85mi
    samples = _stride_sample(coords, stride_miles=10.0)
    assert samples[0] == coords[0]
    assert samples[-1] == coords[-1]


def test_stride_sample_emits_intermediate_points():
    # ~1mi straight line in lat, sampled every 0.5mi → we should
    # see endpoints plus at least one intermediate. The exact count
    # depends on haversine rounding; assert the lower bound.
    base_lat = 37.0
    coords = [(base_lat + i * 0.001, -122.0) for i in range(20)]
    samples = _stride_sample(coords, stride_miles=0.5)
    assert len(samples) >= 3
    assert samples[0] == coords[0]
    assert samples[-1] == coords[-1]


def test_stride_sample_empty_input():
    assert _stride_sample([], stride_miles=5.0) == []


def test_stride_sample_single_point():
    pt = (37.7749, -122.4194)
    assert _stride_sample([pt], stride_miles=5.0) == [pt]


def test_min_distance_to_route_is_min_vertex_distance():
    route = [(37.0, -122.0), (38.0, -122.0)]
    # A point on the line between the two vertices — vertex-min
    # approximation should still produce the smaller of the two
    # haversine distances, which for the midpoint is ~34.5mi.
    midpoint = (37.5, -122.0)
    d = _min_distance_to_route(midpoint, route)
    assert 30 < d < 40


# ---- HTTP-stubbed geosearch + extract -------------------------

# Canned geosearch response: two articles, one near and one far.
_GEOSEARCH_FIXTURE = {
    "query": {
        "geosearch": [
            {"pageid": 111, "title": "San Francisco", "lat": 37.7749, "lon": -122.4194},
            {"pageid": 222, "title": "Coit Tower", "lat": 37.8024, "lon": -122.4058},
        ]
    }
}

# Canned extracts keyed by pageid as a string (matches MediaWiki shape).
_EXTRACT_111 = {
    "query": {
        "pages": {
            "111": {
                "pageid": 111,
                "title": "San Francisco",
                "extract": "San Francisco is a city in California, founded in 1776. Known for the Golden Gate Bridge and the cable cars.",
            }
        }
    }
}
_EXTRACT_222 = {
    "query": {
        "pages": {
            "222": {
                "pageid": 222,
                "title": "Coit Tower",
                "extract": "Coit Tower is an Art Deco tower on Telegraph Hill, built in 1933 as a memorial to volunteer firefighters.",
            }
        }
    }
}


def _fake_handler(request: httpx.Request) -> httpx.Response:
    """httpx.MockTransport handler. Inspects the params dict and
    returns the right canned JSON. Lets us pin the API contract
    without hitting Wikipedia."""
    params = dict(request.url.params)
    action = params.get("list") or params.get("prop")
    if action == "geosearch":
        return httpx.Response(200, json=_GEOSEARCH_FIXTURE)
    if action == "extracts":
        pageid = params.get("pageids")
        if pageid == "111":
            return httpx.Response(200, json=_EXTRACT_111)
        if pageid == "222":
            return httpx.Response(200, json=_EXTRACT_222)
        return httpx.Response(200, json={"query": {"pages": {}}})
    return httpx.Response(404, json={"error": "unrecognized request"})


@pytest.mark.asyncio
async def test_geosearch_along_polyline_returns_dedupe_extracts():
    # A trivial polyline of two SF coords. Every sample will hit
    # the same geosearch fixture, so by-pageid dedupe should
    # collapse N samples × 2 results → 2 unique FactCandidates.
    transport = httpx.MockTransport(_fake_handler)
    client = httpx.AsyncClient(transport=transport)
    service = WikipediaFactsService(client=client)

    # encoded "_p~iF~ps|U_ulLnnqC" is roughly a short SF segment;
    # easier here to bypass decoding by patching it. We want the
    # parse contract, not the decoder (which has its own tests).
    fake_coords = [(37.7749, -122.4194), (37.8024, -122.4058)]
    with patch(
        "app.services.wikipedia_facts.decode_polyline",
        return_value=fake_coords,
    ):
        candidates = await service.geosearch_along_polyline(
            "anyhandle", stride_miles=1.0,
        )

    await service.close()

    assert len(candidates) == 2
    titles = {c.title for c in candidates}
    assert titles == {"San Francisco", "Coit Tower"}
    # pageid-stable ordering: lowest first
    assert candidates[0].wikipedia_pageid == 111
    assert candidates[1].wikipedia_pageid == 222
    # Each candidate has a URL pointing back to Wikipedia
    assert candidates[0].url == "https://en.wikipedia.org/?curid=111"
    # Extracts present
    assert "San Francisco" in candidates[0].extract
    assert "Coit Tower" in candidates[1].extract


@pytest.mark.asyncio
async def test_empty_polyline_returns_empty_list():
    service = WikipediaFactsService(client=httpx.AsyncClient())
    with patch(
        "app.services.wikipedia_facts.decode_polyline",
        return_value=[],
    ):
        candidates = await service.geosearch_along_polyline("anything")
    await service.close()
    assert candidates == []


@pytest.mark.asyncio
async def test_geosearch_http_error_is_swallowed_not_raised():
    # A single geosearch failure shouldn't abort the whole route.
    # Returning an empty list is the safer default — the route
    # might still produce candidates from other sample points.
    def _failing_handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, json={"error": "boom"})

    transport = httpx.MockTransport(_failing_handler)
    client = httpx.AsyncClient(transport=transport)
    service = WikipediaFactsService(client=client)
    with patch(
        "app.services.wikipedia_facts.decode_polyline",
        return_value=[(37.7749, -122.4194)],
    ):
        candidates = await service.geosearch_along_polyline("anything")
    await service.close()
    assert candidates == []


def test_fact_candidate_article_length():
    c = FactCandidate(
        wikipedia_pageid=1,
        title="X",
        lat=0, lng=0,
        distance_from_route_miles=0,
        extract="hello world",
        url="https://en.wikipedia.org/?curid=1",
    )
    assert c.article_length == len("hello world")
