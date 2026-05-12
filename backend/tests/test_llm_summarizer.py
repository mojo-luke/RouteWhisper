"""Tests for the LLM summarizer.

We do not contact Anthropic in tests — the client is injected as a
mock so we can drive happy-path, malformed-output, and exception
paths deterministically. The contract being pinned:
  - Valid JSON → SummaryBundle
  - Fenced JSON → SummaryBundle
  - Junk text → fallback bundle with is_thin=True
  - Anthropic exception → fallback bundle with is_thin=True
  - Empty extract → fallback bundle with title hint
"""

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from anthropic import AnthropicError

from app.services.llm_summarizer import (
    LLMSummarizer,
    SummaryBundle,
    _strip_fences,
    _first_json_object,
)


def _fake_response(text: str):
    """Build an object shaped like an Anthropic Messages response.
    The real SDK returns `Message` with `.content: list[ContentBlock]`,
    each block having `.type` and `.text`. We mirror that surface."""
    block = SimpleNamespace(type="text", text=text)
    return SimpleNamespace(content=[block])


def _client_returning(text: str) -> MagicMock:
    client = MagicMock()
    client.messages.create.return_value = _fake_response(text)
    return client


def test_parses_clean_json():
    json_text = (
        '{"primary": "Auburn was a Gold Rush boomtown — its hardware '
        'store still has the original 1850s safe behind the counter.", '
        '"follow_ups": ["The town was a key stop on the stagecoach line.", '
        '"It hosts a parade every July."], "is_thin": false}'
    )
    summarizer = LLMSummarizer(client=_client_returning(json_text))
    bundle = summarizer.summarize_article("Auburn, California", "rich extract text")
    assert isinstance(bundle, SummaryBundle)
    assert "Gold Rush" in bundle.primary
    assert len(bundle.follow_ups) == 2
    assert bundle.is_thin is False


def test_parses_json_wrapped_in_code_fence():
    # Some models wrap JSON in markdown fences despite being told not
    # to. We strip them rather than treat as a malformed response.
    fenced = (
        "```json\n"
        '{"primary": "X.", "follow_ups": [], "is_thin": true}\n'
        "```"
    )
    summarizer = LLMSummarizer(client=_client_returning(fenced))
    bundle = summarizer.summarize_article("Anywhere", "extract")
    assert bundle.primary == "X."
    assert bundle.is_thin is True


def test_parses_json_with_leading_preamble():
    # Model adds a sentence before the JSON despite instructions —
    # _first_json_object still locates the {} block and parses it.
    text = (
        "Sure, here's the summary:\n\n"
        '{"primary": "Place X.", "follow_ups": ["More."], "is_thin": false}'
    )
    summarizer = LLMSummarizer(client=_client_returning(text))
    bundle = summarizer.summarize_article("Place X", "extract")
    assert bundle.primary == "Place X."
    assert bundle.follow_ups == ["More."]


def test_falls_back_when_response_is_not_json():
    summarizer = LLMSummarizer(client=_client_returning("This is not JSON at all."))
    extract = "Auburn is a city in Placer County, California. The town was founded during the California Gold Rush."
    bundle = summarizer.summarize_article("Auburn", extract)
    # Fallback uses first sentence of extract + is_thin=True
    assert bundle.is_thin is True
    assert "Placer County" in bundle.primary
    assert bundle.follow_ups == []


def test_falls_back_when_json_fails_schema():
    # Valid JSON but wrong shape — primary missing entirely.
    bad = '{"summary": "no primary key", "follow_ups": []}'
    summarizer = LLMSummarizer(client=_client_returning(bad))
    bundle = summarizer.summarize_article("X", "Some extract here.")
    assert bundle.is_thin is True
    assert "Some extract" in bundle.primary


def test_falls_back_on_anthropic_exception():
    client = MagicMock()
    client.messages.create.side_effect = AnthropicError("boom")
    summarizer = LLMSummarizer(client=client)
    bundle = summarizer.summarize_article("X", "First sentence. Second sentence.")
    assert bundle.is_thin is True
    assert bundle.primary == "First sentence."


def test_handles_empty_extract():
    # No extract → still returns a valid bundle, just a title-based
    # placeholder. The narration_card will probably never reach this
    # case because the ranker would drop empty-extract candidates,
    # but defense-in-depth.
    summarizer = LLMSummarizer(client=MagicMock())
    bundle = summarizer.summarize_article("Mystery Place", "")
    assert bundle.is_thin is True
    assert "Mystery Place" in bundle.primary
    # We never even called the LLM
    assert not summarizer._client.messages.create.called  # type: ignore[attr-defined]


def test_truncates_long_extracts_before_sending():
    # Article longer than _MAX_EXTRACT_CHARS should be trimmed in
    # the user message — we don't want to spend tokens on stub-tail
    # sections. Easiest check: capture the call args.
    text = '{"primary": "ok", "follow_ups": [], "is_thin": true}'
    client = _client_returning(text)
    summarizer = LLMSummarizer(client=client)
    huge_extract = "Aa. " + ("Bb. " * 5000)  # ~20kb
    summarizer.summarize_article("Big article", huge_extract)
    call_kwargs = client.messages.create.call_args.kwargs
    user_content = call_kwargs["messages"][0]["content"]
    # Should contain the start; should not contain the full 20kb
    assert "Aa." in user_content
    assert len(user_content) < 5000  # well under huge_extract length


def test_strip_fences_helpers():
    assert _strip_fences("```json\n{}\n```") == "{}"
    assert _strip_fences("```\n{}\n```") == "{}"
    assert _strip_fences("plain") == "plain"


def test_first_json_object_helper():
    assert _first_json_object('blah {"a": 1} blah') == {"a": 1}
    assert _first_json_object('no json here') is None
    # Nested braces are handled
    assert _first_json_object('{"a": {"b": 2}}') == {"a": {"b": 2}}
