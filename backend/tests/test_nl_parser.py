"""Tests for the canvas NL-command parser (Slice 2: pin_stop / remove_stop).

Unlike LLMSummarizer, nl_parser.py holds a module-level Anthropic client
(not dependency-injected via a constructor) — tests patch
app.services.nl_parser._CLIENT directly rather than passing a client in.

Contract being pinned:
  - Valid pin_stop / remove_stop / unknown JSON -> parsed dict as-is
  - JSON wrapped in a ```json or plain ``` fence -> fence stripped, parsed
    (regression test: this crashed json.loads before nl_parser.py's
    fence-stripping fix)
  - Non-JSON response -> falls back to a friendly "unknown" dict
  - Client raises -> falls back to a friendly "unknown" dict
  - Never raises out to the caller either way
"""

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from app.services.nl_parser import parse_nl_command


def _fake_response(text: str):
    """Shaped like an Anthropic Messages response: `.content[0].text`."""
    block = SimpleNamespace(type="text", text=text)
    return SimpleNamespace(content=[block])


def _client_returning(text: str) -> MagicMock:
    client = MagicMock()
    client.messages.create.return_value = _fake_response(text)
    return client


def test_parses_pin_stop():
    text = '{"type": "pin_stop", "name": "Coffee in Truckee", "location": "Truckee, CA"}'
    with patch("app.services.nl_parser._CLIENT", _client_returning(text)):
        result = parse_nl_command("add a coffee stop in Truckee")
    assert result == {
        "type": "pin_stop",
        "name": "Coffee in Truckee",
        "location": "Truckee, CA",
    }


def test_parses_remove_stop():
    text = '{"type": "remove_stop", "name_pattern": "Coffee in Truckee"}'
    with patch("app.services.nl_parser._CLIENT", _client_returning(text)):
        result = parse_nl_command("remove the coffee stop")
    assert result == {"type": "remove_stop", "name_pattern": "Coffee in Truckee"}


def test_parses_unknown():
    text = '{"type": "unknown", "message": "Not sure what you mean."}'
    with patch("app.services.nl_parser._CLIENT", _client_returning(text)):
        result = parse_nl_command("do something weird")
    assert result == {"type": "unknown", "message": "Not sure what you mean."}


def test_strips_json_code_fence():
    fenced = (
        "```json\n"
        '{"type": "pin_stop", "name": "Lunch in Reno", "location": "Reno, NV"}\n'
        "```"
    )
    with patch("app.services.nl_parser._CLIENT", _client_returning(fenced)):
        result = parse_nl_command("add lunch in reno")
    assert result == {
        "type": "pin_stop",
        "name": "Lunch in Reno",
        "location": "Reno, NV",
    }


def test_strips_plain_code_fence_without_language_tag():
    fenced = (
        "```\n"
        '{"type": "remove_stop", "name_pattern": "Lunch in Reno"}\n'
        "```"
    )
    with patch("app.services.nl_parser._CLIENT", _client_returning(fenced)):
        result = parse_nl_command("remove lunch in reno")
    assert result == {"type": "remove_stop", "name_pattern": "Lunch in Reno"}


def test_falls_back_to_unknown_on_non_json_response():
    with patch("app.services.nl_parser._CLIENT", _client_returning("not json at all")):
        result = parse_nl_command("garble garble")
    assert result["type"] == "unknown"
    assert "couldn't understand" in result["message"].lower()


def test_falls_back_to_unknown_on_client_exception():
    client = MagicMock()
    client.messages.create.side_effect = RuntimeError("boom")
    with patch("app.services.nl_parser._CLIENT", client):
        result = parse_nl_command("add a stop somewhere")
    assert result == {
        "type": "unknown",
        "message": "Something went wrong. Please try again.",
    }


def test_sends_stripped_input_text():
    text = '{"type": "unknown", "message": "n/a"}'
    client = _client_returning(text)
    with patch("app.services.nl_parser._CLIENT", client):
        parse_nl_command("  add a stop in Tahoe  \n")
    sent = client.messages.create.call_args.kwargs["messages"][0]["content"]
    assert sent == "add a stop in Tahoe"
