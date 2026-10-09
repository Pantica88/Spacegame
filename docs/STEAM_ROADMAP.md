# From flight prototype to Steam game

APHELION is a working title, not a cleared commercial name. Bluffton Flight Works is the game's fictional space-program identity, not a legal business entity. This repository establishes an original 3D building-and-flight loop. It is not a finished product or a guarantee of Steam approval or sales.

## Product direction

**Make a small space program where a satisfying flight ends with bringing the capsule home.**

Players choose a mission, assemble a rocket, pilot it, recover the capsule, and use what they learned to improve the next design. A compact planet and quick iteration keep the focus on readable engineering choices and entertaining flights. Own the visual identity, writing, part designs, and progression. The reference to Kerbal Space Program describes the player's interest; this project does not use its branding, characters, artwork, or code.

The first commercial scope should prove one planet and a meaningful set of missions before adding more celestial destinations. Multiplayer, a full solar system, complex structural simulation, and mod tooling would each expand production substantially. Decide on them only after the core game earns that investment through playtests.

## What exists now

The foundation includes configurable rocket stacks, three engine choices, optional boosters and fins, 3D launch and flight, central gravity, fuel and drag, capsule separation and recovery, an orbital map, three starter contracts, and local progress saving. There is procedural engine audio, a sound toggle, manual pause, and fullscreen support. Desktop export presets establish a packaging path. These features need broader testing, balancing, and art direction before they can support a commercial release.

The starter contracts cover a 1 km recovery flight, a 12 km recovery flight, and a closed orbit above the 90 km atmosphere. The orbital contract does not require recovery. A saved profile preserves the latest design, records, and completed contracts; it does not resume an active flight. The [README](../README.md) includes tested starter flight profiles.

## Product gates

| Gate | Work to complete | Evidence before moving on |
| --- | --- | --- |
| Core fun | Tune controls, camera, engine feedback, recovery, and design tradeoffs; teach pitch-over and staging | New players can build, launch, and recover without developer help; they voluntarily make another design |
| Vertical slice | Add a cohesive art and audio pass, guided first mission, clearer flight failures, part descriptions, and a small mission sequence | External players can complete a representative session and explain the game's appeal |
| Full game | Build the agreed mission progression, unlocks, viable part choices, a saved craft library, flight saving, and robust recovery rules | All promised features work end to end; campaign completion and replayability are tested |
| Desktop quality | Rebindable controls, controller navigation, UI scaling, readability options, graphics/audio settings, pause/focus handling, save migration and corruption recovery | Tested Windows and Linux builds across target hardware and resolutions; repeatable save/load and long-session QA |
| Steam candidate | Final identity, asset/license records, store screenshots and trailer, capsule/library art, localization scope, content survey, system requirements, tested depots and launch options | Store description accurately matches the tested build; both Steam release checklists are complete and approved |

Steam achievements, Cloud saves, and Steam Input are useful integration candidates. Scope and validate them explicitly; this prototype currently has no Steamworks integration. Steam Deck support should follow real device testing and controller work, rather than being inferred from a successful Linux export.

Do not announce a price or release date solely from the existence of this prototype. Use player feedback, finished content, testing results, and a realistic production plan to make those decisions. Early Access also requires a game that buyers can meaningfully play today, with an accurate account of what is unfinished.

## Steam process

Verified against Valve's public documentation on **2026-09-07**. Recheck these requirements when preparing the actual release.

1. **Onboard the actual publisher.** Steamworks requires digital agreements, identity verification, and bank and tax information. The current per-product Steam Direct fee is **US$100 or equivalent**. Valve lists a **30-day wait after the fee payment** for the first few releases and a public **Coming Soon page for at least two weeks** before release. These are platform timing requirements, not a development schedule. [Valve: Onboarding](https://partner.steamgames.com/doc/gettingstarted/onboarding)
2. **Prepare the store and the build.** Complete the separate store-presence and build/configuration checklists. Submit the store page for review before submitting the build; both must be reviewed and approved before launch. The build should contain the features described on the store page. [Valve: Release Process](https://partner.steamgames.com/doc/store/releasing)
3. **Allow review and correction time.** Valve currently describes store reviews as typically taking 3–5 business days and recommends submitting at least seven days before the intended page publication. After approval and the required public Coming Soon period, release remains an explicit publisher action. [Valve: Release Process](https://partner.steamgames.com/doc/store/releasing)

No Steam account, application, store page, purchase, depot upload, or release has been created by this project setup. Publisher onboarding, fees, commercial naming decisions, and any eventual publication are separate business actions.

## Ownership and assets

Keep a source and license record for every external asset, font, plugin, audio file, and dependency added. Review the working title and studio identity before investing in store assets. Keep the game and its presentation distinct from the reference game. Godot supports commercial distribution under its MIT license; distribute the required engine and component notices with the build. [Godot: License](https://godotengine.org/license/)
