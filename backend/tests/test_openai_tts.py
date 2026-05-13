"""Tests for the OpenAI TTS wrapper.

We do not contact OpenAI in tests — the client is stubbed so we can
exercise the success path, an empty-response path, and exception paths
deterministically. Contract being pinned:

  - text → mp3 bytes on success
  - empty/whitespace input short-circuits (no API call)
  - OpenAIError returns None (caller falls back to local TTS)
  - empty/missing audio body returns None
"""

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from openai import OpenAIError

from app.services.openai_tts import TtsSynthesizer


def _client_returning(audio_bytes: bytes) -> MagicMock:
    client = MagicMock()
    client.audio.speech.create.return_value = SimpleNamespace(content=audio_bytes)
    return client


def test_synthesize_returns_bytes_on_success():
    client = _client_returning(b"\x49\x44\x33fake-mp3-bytes")
    tts = TtsSynthesizer(client=client)
    result = tts.synthesize("So this place was a Gold Rush boomtown.")
    assert result == b"\x49\x44\x33fake-mp3-bytes"

    # Verify we asked for the right model + voice + format on the
    # primary attempt, and that the tone instructions were attached.
    args = client.audio.speech.create.call_args.kwargs
    assert args["model"] == "gpt-4o-mini-tts"
    assert args["voice"] == "nova"
    assert args["response_format"] == "mp3"
    assert "instructions" in args
    assert "shotgun" in args["instructions"].lower()


def test_falls_back_to_tts_1_hd_when_primary_model_unavailable():
    # Simulate the model being unavailable on this account: primary
    # call raises OpenAIError, second call (fallback) succeeds.
    client = MagicMock()
    primary_error = OpenAIError("model gpt-4o-mini-tts not found")
    success_response = SimpleNamespace(content=b"fallback-audio")
    client.audio.speech.create.side_effect = [primary_error, success_response]

    tts = TtsSynthesizer(client=client)
    result = tts.synthesize("text")
    assert result == b"fallback-audio"

    # Two attempts: primary (gpt-4o-mini-tts WITH instructions) then
    # fallback (tts-1-hd WITHOUT instructions — older models reject it).
    assert client.audio.speech.create.call_count == 2
    primary_args = client.audio.speech.create.call_args_list[0].kwargs
    fallback_args = client.audio.speech.create.call_args_list[1].kwargs
    assert primary_args["model"] == "gpt-4o-mini-tts"
    assert "instructions" in primary_args
    assert fallback_args["model"] == "tts-1-hd"
    assert "instructions" not in fallback_args


def test_empty_text_short_circuits_without_api_call():
    client = _client_returning(b"unused")
    tts = TtsSynthesizer(client=client)
    assert tts.synthesize("") is None
    assert tts.synthesize("   ") is None
    assert not client.audio.speech.create.called


def test_openai_error_returns_none():
    client = MagicMock()
    client.audio.speech.create.side_effect = OpenAIError("rate limited")
    tts = TtsSynthesizer(client=client)
    assert tts.synthesize("something") is None


def test_empty_response_audio_returns_none():
    # OpenAI sometimes returns a 200 with an empty body; treat that as
    # a failure rather than letting empty bytes flow downstream.
    client = _client_returning(b"")
    tts = TtsSynthesizer(client=client)
    assert tts.synthesize("text") is None


def test_unexpected_exception_returns_none_not_raise():
    # Defensive: anything weird (network blip, JSON parse) shouldn't
    # crash the route-facts pipeline. Better to surface no audio
    # than no facts at all.
    client = MagicMock()
    client.audio.speech.create.side_effect = RuntimeError("connection reset")
    tts = TtsSynthesizer(client=client)
    assert tts.synthesize("text") is None
