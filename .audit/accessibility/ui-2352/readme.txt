Build 20261031.2352, Xcode 27.1, Shared iPhone 2, iOS 27.0 build 24A434.
Bundle: /var/folders/9j/7d72xt915393rwfg7fzyvv5r0000gn/T/Paeonia-test-1793487122-96256.xcresult
The batch contains 46 UI cases and 3 presence tests. UI: 23 passed, 23 failed.
All 3 presence cases passed. No audit issue was ignored.

The first AX5 answer audit completed without audit findings, but Settings
restoration failed. Fourteen subsequent audits and two AX5 journeys failed to
establish the requested Settings state. Their app screens were not audited.
Native Settings exposed zero-sized inner row buttons and retained a scrolled
position. The helper now uses nonzero native rows, scrolls toward their observed
position and confirms the destination navigation bar before continuing.

Six feature journeys failed: Consensio's parent identifier overwrote Lock in;
Guess my spot's waiting container overwrote its description-reader identifier;
drawing description controls were below a gesture canvas at AX5; Ultimate
Tic-Tac-Toe's hidden/disabled button remained queryable after a committed move;
First Steps did not dismiss; onboarding could not find the photo grid while
global text size remained AX5. These require focused repeats. Photos already
contains six simulator sample images. No personal photo or new fixture was added.

Two runtime warnings report invalid frame dimensions during drawing composition
and story correction. This build predates integration of main's Home map fallback
and header changes. Repeat on the combined source; do not waive the warnings.
