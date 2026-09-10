# Next milestone: a first flight players can finish themselves

After fixing the planet rendering transition, aim for a polished 15–20 minute session: choose a rocket, launch, separate, recover, improve the design, and fly again. Keep the next milestone on the current planet with the existing parts and missions.

1. **Verify the view through a whole flight.** Fly slowly through the reported altitude range on ascent and descent, orbit and zoom the camera, and switch to the map and back. Repeat at higher altitude and near the surface. Check for missing geometry, abrupt horizon changes, and flickering; validate a packaged Linux build and a real Windows run.
2. **Guide the first recovery mission.** Teach one action at a time, show why it matters, and explain the parachute's safe deployment conditions. Let players retry quickly after a crash. Success means a new player can complete the first mission without reading the README or asking the developer for help.
3. **Make staging predictable.** Show what the next Space press will do and which parts will separate. Explain recovery failures and show enough flight results to suggest a useful design change. Players should be able to predict capsule separation before pressing the key.
4. **Add a small craft library.** Name, save, load, and duplicate several rocket designs so the player can compare flights without rebuilding a successful craft. Preserve existing progress and the current saved design when this feature is introduced.

Run the session with 3–5 people who have not seen the project. Record where they hesitate, accidental staging, recovery failures, whether they understand the results, and whether they choose to make a second rocket. Address the repeated problems before adding destinations or a much larger parts list. This plan describes upcoming work; the guided mission and craft library are not implemented yet.
