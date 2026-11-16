# M1 checklist: does the mod pak load?

Already done for you: the pak is in `Content\Paks\~mods` and the scripts are in the UEVR
profile. This is the same setup as M0: nightly 01143, Native Stereo, DX12.

1. Start Dreadmoor and inject UEVR the same way as M0. Stand inside the playspace.
2. Load your save and walk around for a few seconds.
3. Expected about 2 seconds after you're on foot:
   - a grey cube, half a metre wide, about 1.5 m in front of where you were looking
   - the white text `DreadmoorVR pak loaded` in the top left for 10 seconds
     (it may only show on the desktop mirror)
4. Note which of the two you saw: both, the cube only, the text only, or neither.
5. Say "done". I'll read the UEVR log for `[DreadmoorVR]` lines, which say which load method
   worked or why it failed, and the game log for whether the pak mounted.

The probe still runs too, so if you fire the hook gun once, its drag numbers get logged.
