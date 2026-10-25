# Interface direction — 25 October 2026

Richard requested a simpler interface informed by Recursive Systems Elixir.
Reference inspected at `10f75ce1450315f39b7826aa41071bb771fdd850`:
`assets/css/app.css` and `docs/project-context/01-consulting-product-and-interface.md`.
The reference project is unchanged. This app retains its Flutter/C++ architecture.

## Visual language

- Neutral background `#faf9f8`, white surfaces, ink `#201f1e`, secondary text
  `#605e5c`, and a single interaction blue `#0f6cbd`.
- Flat bordered surfaces, 4px corners, restrained status colours and no routine
  card shadows. Clear 14px body, 16px row titles and 28px page headings.
- Compact command area, readable router rows and generous spacing between tasks.
  Touch targets remain at least 44px high; desktop density is not copied onto phones.

## Main task

Find routers → add authorized credentials → check a selected router.

The default view should show what was found, what has been checked and the next
action. Read-only scope stays visible. Thread version, endpoint state, protocol
codes and exact timestamps belong in expandable details. Reports remain secondary
and exclude credentials and household identifiers.

Advertisements are observations. A matching name does not prove a shared network.
Only a completed authenticated matching read earns a verified state. Mismatch,
timeout, partial, unsupported and not checked remain distinguishable by text and
icon, not colour alone. Network joining stays disabled and has one modest footer
control rather than repeated promotional panels.

Google Home has a documented mobile integration route but is not connected in this
build. See GOOGLE-HOME.md. Future credential providers should remove manual dataset
entry from the ordinary path; until implemented, the interface must say what is
actually available.

Verification includes narrow and desktop layouts, long names, enlarged text,
loading/error/unsupported states, detail disclosure, credential clearing, report
redaction and the disabled join control. Visual checks are separate from unit tests.
