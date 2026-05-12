"""Tests for the fact ranker.

The contract being pinned:
  - Stub articles (< _STUB_CHAR_THRESHOLD chars) lose badly to
    full-length ones
  - On-route articles beat off-route at the same length
  - User interest matches lift articles that would otherwise score
    in the middle
  - top_n caps the returned list
  - Empty input is handled
"""

from app.services.fact_ranker import (
    DEFAULT_TOP_N,
    RankedFact,
    rank_candidates,
    _score_uniqueness,
    _score_local_relevance,
    _score_interest_fit,
    _normalize_interests,
)
from app.services.wikipedia_facts import FactCandidate


def _candidate(
    *,
    pageid: int = 1,
    title: str = "Test",
    extract: str = "Some extract text.",
    distance: float = 1.0,
) -> FactCandidate:
    """Test-helper builder. Keeps test bodies focused on what's
    actually being varied per case."""
    return FactCandidate(
        wikipedia_pageid=pageid,
        title=title,
        lat=37.0,
        lng=-122.0,
        distance_from_route_miles=distance,
        extract=extract,
        url=f"https://en.wikipedia.org/?curid={pageid}",
    )


def test_full_article_beats_stub():
    stub = _candidate(pageid=1, title="Stubville", extract="Stubville is a town." * 5)
    full = _candidate(
        pageid=2,
        title="Realtown",
        extract=("Realtown has a long, interesting history. " * 100),
    )
    ranked = rank_candidates([stub, full])
    assert ranked[0].candidate.wikipedia_pageid == 2
    assert ranked[1].candidate.wikipedia_pageid == 1
    # And the gap is significant — uniqueness weight is 0.50, so a
    # stub vs. a full article reliably opens > 0.2 between scores
    # when other dimensions are tied.
    assert ranked[0].score - ranked[1].score > 0.2


def test_on_route_beats_off_route_at_equal_length():
    near = _candidate(pageid=1, extract="x" * 4000, distance=0.5)
    far = _candidate(pageid=2, extract="x" * 4000, distance=20.0)
    ranked = rank_candidates([far, near])
    assert ranked[0].candidate.wikipedia_pageid == 1


def test_interest_match_lifts_a_mid_article():
    # Two equally substantive articles; one mentions the user's
    # interest in its text, one doesn't.
    boring = _candidate(
        pageid=1,
        title="Generic Town",
        extract="A generic article about a generic place. " * 100,
    )
    matched = _candidate(
        pageid=2,
        title="Coffee Town",
        extract="This town is famous for its specialty coffee roasters. " * 100,
    )
    interests = [{"label": "specialty coffee", "keywords": ["coffee", "roaster"]}]
    ranked = rank_candidates([boring, matched], user_interests=interests)
    assert ranked[0].candidate.wikipedia_pageid == 2


def test_no_interests_means_no_interest_fit_score():
    c = _candidate(pageid=1, extract="x" * 4000)
    ranked = rank_candidates([c], user_interests=[])
    assert ranked[0].score_breakdown["interest_fit"] == 0.0


def test_top_n_caps_returned_list():
    cs = [_candidate(pageid=i, extract="x" * 4000) for i in range(50)]
    ranked = rank_candidates(cs, top_n=10)
    assert len(ranked) == 10


def test_default_top_n_is_30():
    assert DEFAULT_TOP_N == 30
    cs = [_candidate(pageid=i, extract="x" * 4000) for i in range(40)]
    ranked = rank_candidates(cs)
    assert len(ranked) == 30


def test_empty_candidates_returns_empty_list():
    assert rank_candidates([]) == []


def test_score_uniqueness_stub_is_low():
    stub = _candidate(extract="x" * 100)
    assert _score_uniqueness(stub) < 0.1


def test_score_uniqueness_long_article_is_high():
    long_one = _candidate(extract="x" * 8000)
    assert _score_uniqueness(long_one) > 0.7


def test_score_local_relevance_distance_decay():
    assert _score_local_relevance(_candidate(distance=0.5)) == 1.0
    # Halfway through the decay band → ~0.5
    mid = _score_local_relevance(_candidate(distance=5.5))
    assert 0.3 < mid < 0.7
    # Beyond the band → 0.0
    assert _score_local_relevance(_candidate(distance=20.0)) == 0.0


def test_score_interest_fit_case_insensitive():
    c = _candidate(title="The COFFEE Capital", extract="famous for ROASTERS")
    score = _score_interest_fit(c, _normalize_interests([
        {"label": "coffee", "keywords": ["roaster"]},
    ]))
    assert score == 1.0


def test_normalize_interests_skips_garbage():
    # Misshapen entries don't blow up the ranker.
    interests = [
        "this is a string not a dict",  # type: ignore[list-item]
        {"label": "valid", "keywords": ["x"]},
        {"label": "", "keywords": []},  # empty label, dropped
        {"keywords": ["only-kws-no-label"]},
    ]
    out = _normalize_interests(interests)  # type: ignore[arg-type]
    assert len(out) == 2  # "valid" + "only-kws-no-label"


def test_score_breakdown_is_present():
    c = _candidate(pageid=1, extract="x" * 4000)
    ranked = rank_candidates([c])
    bd = ranked[0].score_breakdown
    assert set(bd.keys()) == {"uniqueness", "local_relevance", "interest_fit"}
