# Steam Frame camera access for development — 2026-11-18

## Finding

There are three different things people call “camera access,” and only one is a dependable path for our current UEVR-on-PC setup:

1. **Valve tracking dataset (recommended for our calibration sessions).** SteamVR can record headset/controller tracking state and optionally camera video, headset screen video, and audio. Start/stop it in the headset; retrieve the dataset over SSH. This is the supported way to capture the tracking and camera context around a reproducible pose/tracking issue. It is a recording workflow, not a live camera API.
2. **Community direct-camera work (experimental).** A Steam Frame developer describes a SteamOS service that would expose camera frames, camera-to-world transforms and timestamps over shared memory, plus engine SDKs. Their post shows an AprilTag Unity demo, but the project/release was still described as forthcoming when checked. Another developer reports access via a SteamVR driver running as `steamos`; the details conflict with the first developer's planned permission model, so do not assume the service or API is ready.
3. **Passthrough/compositor video (not useful while our PC game replaces passthrough).** The public `frame_handtracking` repo reads `/dev/video99`, which is the final compositor/headset view, not raw camera frames. Its notes say the physical cameras are owned by SteamVR's XRService, SteamVR's public camera API returns no usable frames/calibration on Frame, and opening that stream may break passthrough. In our streamed Dreadmoor session this feed would show the game view, not an exterior view of Bob's elbows.

Arcturus' developer page likewise says a direct camera access API is not available and invites developers to contact them with a use case. Its passthrough blending guidance targets apps running locally on Steam Frame; it does not provide raw camera frames to our streamed Windows/UEVR game.

## Capture workflow for our next rig validation

1. In the SteamVR dashboard, open **Steam overlay → VR Settings → Developer → Record Tracking Data** (enable Advanced Settings if needed).
2. Enable camera video, screen video, and audio if comfortable. Audio lets Bob narrate each pose. Start the capture, dismiss the dashboard, then repeat neutral, T-pose, arms-forward, elbows-at-hips, and hip-fired grapple poses; hold each for several seconds and say the pose name.
3. Stop the capture. Valve stores datasets under `~/.config/openvr/config/cv/xrservice/datasets/`; zip and copy the newest directory over SSH.
4. Compare timestamps and tracked HMD/controller poses with our UEVR arm telemetry. Use camera video for tracking/environment context, not as a guaranteed external body camera view. The headset cameras are outward-facing tracking sensors, so they may not see elbows close to the torso.

The documented SSH recipe is to zip the newest dataset directory on the Frame and `scp` it back. Keep the archive local and inspect its contents before sharing: optional video/audio can contain private room imagery and speech.

## Sources checked

- [Steamworks: Steam Frame Debugging — tracking datasets](https://partner.steamgames.com/doc/steamhardware/steamframe/debugging#tracking-errors) — Valve's capture controls, optional streams, dataset path, and SSH retrieval steps.
- [Arcturus Vision developer resources](https://arcturus.vision/developers) — direct camera API status and local-app passthrough scope.
- [Olivphil/frame_handtracking](https://github.com/Olivphil/frame_handtracking) — community findings on `/dev/video99`, XRService-owned cameras, SteamVR camera API, and direct device limitations (repo reports SteamOS 0.5.6).
- [Community post: easy SLAM camera access for developers](https://www.reddit.com/r/SteamFrame/comments/1x56zex/easy_access_to_slam_cameras_for_developers_soon/) — proposed shared-memory camera service, timestamps/transforms, and the competing SteamVR-driver approach discussed in replies.
- [Community hand-tracking demo using stock SLAM cameras](https://www.reddit.com/r/SteamFrame/comments/1xb6ndx/i_added_hand_overlay_and_steamvr_dashboard/) — developer reports a working native hand-tracking implementation, but the source was not yet published in the post checked.
