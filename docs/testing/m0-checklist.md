# M0 checklist: does UEVR work on Dreadmoor?

This is a go/no-go test, and nothing gets built on top until it passes. Plan on about 30–40
minutes. Tick each line and jot what you saw. Short notes are fine. "Didn't work" is a useful
answer too.

## Before the headset

- [ ] The beta profile contains `plugins\DreadmoorVR.dll`, `scripts\m2_arms.lua`,
      `scripts\m3_gestures.lua`, the `scripts\lib` directory, and `dreadmoorvr_arms_tuning.lua`.
      The production beta intentionally omits the M0 diagnostic probe.
- [ ] Start SteamVR streaming to the Frame.
- [ ] Turn Steam Frame passthrough off before testing. A previous runtime report showed UEVR
      marking the HMD active for only 4.98% of ticks, which can suppress controller input.
- [ ] Start Dreadmoor and load a save where you are on foot, near a fishing spot.
- [ ] Run `Downloads\UEVR\UEVRInjector.exe`, pick `Dreadmoor-Win64-Shipping`, OpenXR, Inject.
- [ ] In the UEVR `log.txt`, confirm `[DreadmoorVR M2] loaded` and `[DreadmoorVR M3] loaded`.
      When the pawn appears, confirm M2 spawns `BP_VRArms`. Record any `FAILED` line.

## In the headset

Each mode: does it render in **stereo** with **head tracking**, and what does the **view** do
(steady, bobbing, turned by the game, stuck)?

- [ ] **On foot:** walk around. Stereo? Tracking? Does the view bob? Can you see your head or
      body clipping?
- [ ] **Controllers:** sticks move and turn, buttons do the game's gamepad actions.
- [ ] **Fishing:** start fishing at a spot.
  - [ ] Hold the trigger and watch the cast power meter. Write down what it does.
  - [ ] Cast, wait for a bite, answer the bite prompt. Write down which button the prompt shows.
  - [ ] Reel (hold the trigger) and fight left and right with the stick. Which way does the
        on-screen indicator move when you push the stick left?
  - [ ] Land the fish. Write down the button.
  - [ ] Turn your head away during a fight. Does the game drag your view back?
  - [ ] While fishing, turn your head left and right. Does the rod and line follow your head?
- [ ] **Crafting bench:** open it, move one item onto the bench and one back. Stereo? Can you
      read it?
- [ ] **Hook gun:** equip it, fire at a floating item, then tap fire repeatedly to drag it in.
  - [ ] Write down the button that fires and the button you tapped.
  - [ ] Did a "twist" prompt ever appear? What did it ask for?
  - [ ] Look at the gun model: where is its crank (side, top, front)?
- [ ] **Boat:** take the wheel, drive a little, get off.
- [ ] **Diving:** if you can reach it, go in and out once.
- [ ] **Frame rate:** does it feel smooth? If not, note which mode.

## After

- [ ] In the UEVR menu (Insert, or both thumbsticks), open the developer section and run
      **Dump SDK**. Note where it says the files went.
- [ ] Close the game normally.
- [ ] Tell me you're done. I'll pick up `dreadmoorvr_m0.log`, the UEVR log and the SDK dump.

## If it fails

If UEVR can't inject, or shows no stereo picture at all, stop there and tell me what you saw.
The next thing to try is the latest UEVR nightly, which needs your OK to download.
