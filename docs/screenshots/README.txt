ThermalScope README screenshot records / README 截图记录

Current set: v1.17.4/en/
Captured: 2026-11-03 (Asia/Shanghai), macOS 27, Apple Silicon.
Application: installed v1.17.4 / build 265, published ARM archive.
Application source commit: a6a76b02abd9a0aeaf313b9dd010fcbf5671e1a4.
Language: English. Appearance: dark, plus one light-mode overview.

These are native window/popover screenshots of the running installed app,
using actual sensor/process readings and session history. They are not
fixture renders, generated images or retouched mockups. Original PNG pixels
were saved directly from the computer-use screenshot API. A macOS remote-
control indicator and pointer may appear in window captures; they belong to
the capture session, not ThermalScope's UI.

Only application UI was captured. No desktop, account pages, authorization
prompts or credentials are included. Values and process names reflect the
capture time and must not be used as current readings or performance claims.
The menu composition and five-card popover are the saved example configuration,
not a claim about factory defaults. Fan control remained System automatic;
no presets, curve edits or fan tests were applied for these screenshots.
Language, theme, menu composition, cards, custom fan curve and sampling
preferences were checked after capture and restored/preserved.

Files:
- overview-dark.png: live metrics, sparklines, warning segments and temperature history.
- overview-light.png: the same dashboard in the light appearance.
- thermal-control.png: five fan presets and the editable temperature/RPM curve.
- sensors.png: readable common sensor names, real trends and inventory/search controls.
- status-panel.png: five compact cards, fan controls and top CPU processes.
- settings.png: menu-bar composition and popover card management.
- cpu-history.png: metric details, sampled history, scale/style and pause controls.

默认 README.md 使用英文，README.zh-CN.md 提供中文说明；两份文档均引用上述
最新版英文实机截图。应用缺省语言仍跟随系统，拍摄结束后已恢复本机原设置。

Historical captures (retained for validation-log references; no longer shown
as current UI in either README):
- status-panel.png: original status-readable-1.16.png, the 1.16 status panel.
- thermal-control.png: original fan-entry-final-1.16.png, the 1.16 control entry.
- cpu-history.png: original cpu-colors-detail-1.15.png, the 1.15 CPU details.
