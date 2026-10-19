# AI summary and activity tree validation

## Scope

Manual Recent work summary with a bounded evidence preview, OpenAI API key in Keychain, one sentence, expandable evidence-linked tree, and local persistence of the latest result. No automated sending, new observation permissions, signing changes, or sandbox changes.

## Validation

- Signed Debug build and all 53 Swift Testing tests passed.
- Input tests verify time filtering, beginning-of-period retention, recent changes, omitted empty attempts, and text/record budgets.
- Tree validation checks known evidence IDs, duplicate citations, parent ordering/cycle rejection, one sentence, node count, and depth.
- Request tests verify the fixed endpoint, text-only input, `store: false`, and absence of the key in the JSON body.
- Fake-transport tests cover successful structured output, refusals, incomplete responses, and safe rate-limit messages.
- Controller tests cover persistence, clearing/reload, corruption preservation, and late-result cancellation.

The signed app was restarted at its normal path. Recent work was verified live with the summary button, period selector, Activity tree default, and existing top navigation; the initial layout was inspected visually. Key entry and a populated model-generated tree were not exercised live.

No real OpenAI request was made, no user key was read by the coding agent, and no API charges were incurred during automated validation. Keychain entry and live account/model access require the user’s key. Model accuracy is not established by mocked tests; evaluate actual summaries against the expandable evidence.

## API references

- [OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses)
- [GPT-4.1 mini support](https://developers.openai.com/api/docs/models/gpt-4.1-mini)
- [OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data)

## Keychain recovery update

The earlier generic read error incorrectly implied every failure was a locked keychain. On-device inspection confirmed the existing production entry was present; after restarting the signed app, its preview successfully reported the saved key without re-entry. The original failure code was not retained, so its exact cause is unconfirmed. The credential was not printed, replaced, or sent to OpenAI.

Keychain calls now run on a dedicated actor. Saving verifies a read-back before showing success. The preview retains the verified key only for that preview/request, avoiding a second Keychain read during sheet dismissal. Authorization cancellation, denial, interaction, unavailable storage, and signing errors have distinct messages with a numeric code and a retry action. Signing settings, the existing item, and app observation permissions are unchanged.

The signed regression suite passed. Three additional Keychain tests cover specific error handling, invalid-key rejection, and a real save/read/update/delete round trip using a unique disposable synthetic entry. They do not access the production credential.
