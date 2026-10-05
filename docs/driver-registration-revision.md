# Revised driver registration flow

The owner rejected the previous experience after using the live emulator. This revision is required before calling the goal complete:

- The first sign-in page explicitly selects passenger or driver mode. Drivers retain passenger booking capability without a passenger gaining driver privileges.
- Registration accepts Arabic names and Arabic/Persian digits, including capacity, phone and other numeric inputs. Existing ASCII-only parsing is removed. Names and free-text descriptions must not be transliterated.
- Driver onboarding is a resumable sequence: identity, vehicle and independent owners, documents with expiry dates, final review, submission confirmation. Each successful step automatically advances.
- Account signup, saved identity, vehicle creation and individual document uploads are drafts. They must not generate administrative application alerts.
- Only the final completed submission creates one administrative review alert. The driver receives a receipt email through a configured transactional email provider; delivery must not be claimed before it is verified.
- Admin vehicle review clearly differentiates draft, submitted, approved and rejected applications. Approval still checks documents, permitted routes and actual capacity on the server.
- A new page layout and Arabic typography must be reviewed on the emulator. Updating palette alone is insufficient.

Already observed: the original live signup and vehicle submission generated separate notices, which the owner explicitly does not want. The first account's email is confirmed and its vehicle exists; preserve this data and migrate it into draft onboarding rather than recreating the account. Never collect the user's password in chat.
