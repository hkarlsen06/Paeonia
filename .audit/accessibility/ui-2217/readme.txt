Build 20261031.2217, Shared iPhone 2, iPhone 17 Pro, iOS 27.0 build 24A434.
Xcode 27.1 build 27A9275. Synthetic local scenarios only.

26 XCTest UI cases completed: 12 passed, 14 failed, none skipped.
Ten audits failed with 37 nodes: 18 contrast, 10 clipped text, six Dynamic
Type, two hit regions and one missing description. Four journeys failed.
No audit issue was ignored. This is not a VoiceOver or Voice Control test.

Retained evidence

summary.json is the unmodified xcresulttool test-results summary.
results.tsv lists every case and outcome, with audit-node counts.
failures.tsv separates audit findings from journey/assertion failures and
records the source changes or investigation still awaiting a repeat.
issues.tsv indexes all 37 nodes by type, identity, label and frame.
issue-details.txt retains their unmodified text attachments, including
hierarchies where the handler could still resolve an element.
settings-diagnosis.txt records the category-override hypothesis and the
native Settings setup prepared for the next run. The hypothesis is unproven.

Passing scope

Five audits passed: Norwegian AX5 answer, English memory detail, Norwegian
AX5 memory editor, privacy and Norwegian AX5 settings. Seven journeys passed:
all three daily-question journeys, one native Four in a Row drop, Ludo native
roll/pawn inspection, and both memory-gallery browse/zoom and retry journeys.
AX5 names identify a requested per-app launch setting, not recorded global
Settings verification in this batch.
These passes do not cover every state, actual authentication or StoreKit,
assistive technology, iPad, or participant usability validation.

Known setup and follow-up

Unlike 2156, Welcome audits attached and returned actual findings. The app
still launched with a per-app preferred-size argument in 2217. Its effect on
audit size changes is not established. Future audits select actual native
Settings sizes and retain state before/after, with every audit type active.
Only particular fixed-font elements were reported; do not infer that every
scaled element failed or that the argument explains the findings.

Several contrast nodes are partly outside the 402 by 874 point viewport.
This requires occlusion/scroll review, not an automatic false-positive label.
The selected 2156 crop measurements cover their named pixels only, not all
2217 contrast nodes. Individual dispositions and the source fixes in
failures.tsv remain pending until the corresponding rerun completes.

Xcode finalized all 26 results after the root agent stopped only its owned
simctl diagnose auxiliary PID 92121 after 2 minutes 35 seconds. It did not
stop the test runner or a test process. The runtime warning about an invalid
frame dimension remains recorded in summary.json and the drawing journey.
Accessibility Inspector again returned a blank pane, with no result.

Original bundle
/var/folders/9j/7d72xt915393rwfg7fzyvv5r0000gn/T/Paeonia-test-1793481465-85398.xcresult
All exported attachments, including screenshots
/tmp/paeonia-ui-2217-all/manifest.json

No VoiceOver, Voice Control, Switch Control, Full Keyboard Access, iPad or
regular assistive-technology user test was performed. No label is verified.
