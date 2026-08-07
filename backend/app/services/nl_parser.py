"""
NL-to-canvas-operations parser for the trip canvas textbox (Slice 2).

Accepts a free-text instruction and returns a structured canvas op dict
that the POST /trips/{id}/nl endpoint executes. Claude Haiku at submit
time — fast, cheap, fires once per user action (not per keystroke).

Slice 2 scope: pin_stop and remove_stop only. Future ops
(set_day_intent, set_lodging, mark_wing_it) decode cleanly to "unknown"
until the day-strip slice ships.
"""

from __future__ import annotations

import json
import logging
import os

from anthropic import Anthropic

logger = logging.getLogger(__name__)

_CLIENT = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))
_MODEL = "claude-haiku-4-5-20251001"
_MAX_TOKENS = 256

_SYSTEM = """\
Parse road-trip planning instructions into structured canvas operations.
Return ONLY a JSON object. No markdown fences, no explanation.

Supported operations:

Add a stop anywhere along the route:
{"type": "pin_stop", "name": "<descriptive stop label>", "location": "<geocodable place or address>"}
Use for: add, include, stop at, visit, I want to see, there's a great X in Y, etc.
"name" should be readable: "Coffee in Truckee" not "Truckee".
"location" must be geocodable: "Truckee, CA" not "there" or "that city".

Remove an existing stop by name:
{"type": "remove_stop", "name_pattern": "<the stop name to match, verbatim or close>"}
Use for: remove, delete, drop, skip, take out, get rid of, etc.

Anything else or ambiguous:
{"type": "unknown", "message": "<friendly 1-sentence note; suggest trying 'add a [type] stop in [city]' or 'remove [stop name]'>"}
"""


def parse_nl_command(text: str) -> dict:
    """Parse a free-text canvas instruction into a structured op dict.

    Returns a dict with at minimum a 'type' key: 'pin_stop', 'remove_stop',
    or 'unknown'. Never raises — errors produce an 'unknown' response.
    """
    raw: str | None = None
    try:
        resp = _CLIENT.messages.create(
            model=_MODEL,
            max_tokens=_MAX_TOKENS,
            system=_SYSTEM,
            messages=[{"role": "user", "content": text.strip()}],
        )
        raw = resp.content[0].text.strip()
        if raw.startswith("```"):
            lines = raw.splitlines()
            raw = "\n".join(lines[1:-1]).strip()
        return json.loads(raw)
    except json.JSONDecodeError:
        logger.warning("NL parser returned non-JSON: %r", raw)
        return {
            "type": "unknown",
            "message": (
                "I couldn't understand that. "
                "Try: 'add a coffee stop in [city]' or 'remove [stop name]'."
            ),
        }
    except Exception as e:
        logger.error("NL parser error: %s", e)
        return {"type": "unknown", "message": "Something went wrong. Please try again."}
