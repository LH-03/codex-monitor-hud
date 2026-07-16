# Codex Micro color reference

The optional `codexMicro` status scheme is a local visual reference, not an official OpenAI HUD palette.

## Source and values

The five values were sampled from the visible RGB status presentation on OpenAI's public [Codex Micro × Work Louder page](https://openai.com/supply/co-lab/work-louder/) on 2026-07-16:

| Reference value | HUD use |
| --- | --- |
| white `#FFFFFF` | idle |
| green `#9BF396` | completed |
| blue `#9CD5FE` | active |
| peach `#FFD0B8` | listening and paused |
| red `#FF7373` | error and aborted |

The source page presents RGB status effects. It does not publish a seven-state HUD mapping for this project, so the two repeated mappings above are this project's own local choices.

## Important limitations

- This is a visual reference only. It does not imply affiliation with, endorsement by, or approval from OpenAI or Work Louder.
- OpenAI has not provided this project with an official software palette, calibration target, or guarantee of color matching.
- Browser rendering, monitor gamut/profile, HDR, operating-system color management, accessibility transformations, transparency, theme backgrounds, and hardware LEDs can all produce a different visible result. Matching the page or physical Codex Micro lighting is not guaranteed.

The scheme remains fully editable in Settings. Select another scheme or customize individual ARGB values if a different result is needed.
