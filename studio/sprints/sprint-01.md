# Sprint 1 report: Foundations + rolling slice (code)
**Date:** 2026-11-07   **Result:** All code tasks are done and reviewed. The playable demo still needs Studio (assets, StarterPickUI, playtest).

## Done
- T-002 toolchain: Rojo project, aftman (rojo, selene, stylua, lune), loaders, Utilities, vendored ProfileStore/Trove, lune test harness.
- T-029 all GDD Tables · T-030 BallStats + consistency specs.
- T-003 Network (token bucket) + PlayerData (ProfileStore, DataTemplate, client mirror).
- T-005 BallService/BallController (feel port, stat attributes, speed audit) · T-031 ObstacleController + CameraController.
- T-006a CourseService (picker, chaining, fall zones, SegmentTest) · T-006b ProgressService + RoundService.
- T-007 InventoryService + OnboardingService · T-022 Cmdr AdminService (F2).
- T-008 reviews (a/b/d) and fixes (c/e): 12 must-fixes resolved. Among them: a rejoin exploit, StreamingEnabled ball binding, and array paths.

## Verification
`lune run tests` gives 170 passed, 0 failed. selene is clean and rojo builds. **No Studio playtest yet**, because the Studio MCP wasn't connected.

## Blocked / carried over
T-004 asset port, StarterPickUI, the M1 feel test (AnchorTopSpeed = 40 and JumpVelocityScale = 200 are placeholders), and T-009 QA.
