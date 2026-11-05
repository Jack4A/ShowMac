# ShowMac 1.18.7 UI previews

Rendered on November 5, 2026, from the actual shared SwiftUI views for build 274 on macOS 27. These are offscreen UI previews using isolated, deterministic sample readings, not screenshots of live hardware measurements. The local capture harness selects English or Simplified Chinese and configures five example cards with fan controls visible and process rankings hidden. No user preferences or hardware controls are changed by rendering.

- `en/`: English interface; light/dark menu bar panel, thermal control and the scene manager.
- `zh/`: Simplified Chinese equivalents.

The new previews show the unified fan mode selector, duration, Switch by app control, and Scenes & apps management. Hardware launch/quit/manual-override checks were separately performed with a temporary Calculator rule on the installed Apple Silicon build; that rule was removed afterwards. The website builder uses these versioned assets only for releases at or after 1.18.7. Earlier dashboard/sensor screenshots retain their original capture provenance.
