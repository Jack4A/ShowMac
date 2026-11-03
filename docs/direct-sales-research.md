# Direct sales research — November 4, 2026

These are observations from the vendors' own sites and live purchase interfaces, not reseller prices. The browser checkout country was United States; amounts are USD display prices before the final location-dependent tax calculation. Promotions, currency and regional pricing can change. No purchaser data was entered and no purchase was completed.

| Product | Observed direct price | Commercial model |
| --- | --- | --- |
| [iStat Menus 7](https://bjango.com/mac/istatmenus/) | Single US$11.99; family US$14.99 | 14-day trial, then a paid license. Family offer covers up to five family members; includes six months of weather. Major-version upgrades can be paid. |
| [CleanMyMac](https://macpaw.com/store/cleanmymac) | One Mac: US$39.95/year or US$119.95 once | Subscription and one-time options, with multi-Mac plans. One-time licenses cover the current major version; future major upgrades are separate. |
| [Macs Fan Control](https://crystalidea.com/macs-fan-control/buy) | macOS Pro US$14.95; macOS + Windows US$24.95 | Free core app, paid custom fan presets and priority support. Pro is a one-time purchase per computer. |

## Checkout and activation

All three direct purchase flows use Paddle. iStat Menus and CleanMyMac were opened as actual Paddle checkout overlays; Macs Fan Control explicitly names Paddle as its merchant of record on its buy page. Bjango's [privacy policy](https://bjango.com/privacy/) also lists Paddle. The user's own personal payment QR codes are not equivalent to these hosted checkout flows.

Macs Fan Control's [activation guide](https://crystalidea.com/macs-fan-control/activate-pro-version) describes entering the purchase email and delivered license code in the app. CleanMyMac's [purchase options](https://macpaw.com/support/cleanmymac/knowledgebase/purchase-options) distinguish perpetual use of the purchased version from subscription access to future major versions. Its [edition comparison](https://macpaw.com/support/cleanmymac/knowledgebase/editions) documents a seven-day full-feature trial. iStat Menus documents its [paid major-version upgrade policy](https://bjango.com/help/istatmenus7/update/).

Paddle's public [standard pricing](https://www.paddle.com/pricing) is 5% + US$0.50 per checkout. At a US$1 sale, that example fee alone leaves US$0.45, before taxes and any other applicable charges; this is not a claim about the vendors' negotiated rates. Low-value software should seek a suitable commercial rate rather than assuming their rates match public pricing.

Paddle documents [identity verification for individuals and sole traders](https://www.paddle.com/help/start/account-verification/what-is-identity-verification). That does not guarantee approval of this seller or product. [Alipay acceptance](https://developer.paddle.com/concepts/payment-methods/alipay/) requires additional Paddle approval, a China customer address and CNY pricing. Do not promise that Chinese payment methods will be available before the account is approved.

An implementation caveat: Paddle's old [Mac trial and licensing SDK guidance](https://www.paddle.com/help/start/intro-to-paddle/selling-a-mac-app-with-trials-and-licensing) is explicitly for Paddle Classic. Do not assume the existing vendors' old SDK or automatic serial delivery is available to a newly created Paddle Billing account. Confirm the account product first, then implement payment verification and license issuance using the supported integration.

## Proposed ShowMac experience, not yet implemented

The recommended customer flow is a full-feature evaluation followed by one one-time purchase, an emailed license and a native activation entry in settings. Avoid multiple paid tiers or subscriptions for the initial small utility. The owner has fixed the intended price at CNY 5.90 / USD 1.00; the trial duration, device limit, transfer rights, major-upgrade policy and refund terms have not been agreed and must not be advertised as settled.

The bilingual purchase preparation page is committed but checkout remains closed. No payment account, order webhook, license service or app activation gate is connected. The current downloadable developer preview is still free to download and is not a paid/licensed release.
