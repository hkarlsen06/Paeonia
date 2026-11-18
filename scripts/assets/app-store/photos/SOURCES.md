# Photo sources

`scripts/app-store-content` uploads these photos to the test couple's account for App Store screenshots. Each one is from Unsplash under the [Unsplash License](https://unsplash.com/license). They were downloaded from the Unsplash image CDN at 1600 px on the long edge.

| File | Photo page | Photographer |
|---|---|---|
| `cabin-lake.jpg` | https://unsplash.com/photos/black-cabin-in-pine-forest-4wkbv_PlSik | [Barnabas Davoti](https://unsplash.com/@davotibarna) |
| `cabin-living-room.jpg` | https://unsplash.com/photos/cozy-living-room-with-wooden-walls-AoWV295_E7w | [Ahmet Yüksek](https://unsplash.com/@ahmetyuksek) |
| `cabin-cocoa.jpg` | https://unsplash.com/photos/a-person-holding-a-cup-of-coffee-next-to-a-plate-of-cookies-ar3LJ6tYeUY | [Elin Gann](https://unsplash.com/@elsekind) |
| `copenhagen-nyhavn.jpg` | https://unsplash.com/photos/colorful-buildings-line-a-canal-with-boats-in-copenhagen-u50ivaFTJ5U | [Vincenzo Inzone](https://unsplash.com/@vincent_61) |
| `copenhagen-cafe.jpg` | https://unsplash.com/photos/a-cup-of-coffee-and-some-pastries-on-a-table-G36pUixWrOA | [Simon Follin](https://unsplash.com/@simonfollin) |
| `beach-dunes.jpg` | https://unsplash.com/photos/a-sandy-beach-next-to-the-ocean-under-a-cloudy-sky-7gsDvwtB_oQ | [Sebastian Puskeiler](https://unsplash.com/@keiler) |
| `beach-ice-cream.jpg` | https://unsplash.com/photos/a-hand-holding-an-ice-cream-cone-in-front-of-a-blue-sky-QF03mdb14QI | [Yuika Takamura](https://unsplash.com/@blue_hamberts) |
| `question-cat.jpg` | https://unsplash.com/photos/a-fluffy-grey-cat-sits-on-a-windowsill-looking-out-7wNZYV2nHgc | [Sarah Windeler](https://unsplash.com/@hyggepause) |
| `question-snow.jpg` | https://unsplash.com/photos/a-city-street-is-covered-in-snow-at-night--qv6y0uwihE | [Alexander Fastovets](https://unsplash.com/@darkmoon_afa) |
| `question-tulips.jpg` | https://unsplash.com/photos/fresh-tulips-are-displayed-in-paper-bags-WYlu98J-oN4 | [Eugenia Pan'kiv](https://unsplash.com/@eugenivy_now) |
| `question-bike.jpg` | https://unsplash.com/photos/a-bicycle-is-parked-next-to-a-bush-of-flowers-CAG2fOmgrhk | [Anya Chernykh](https://unsplash.com/@anyachernykh) |

`elena-portrait.jpg` is not a photo of a real person. It was generated with Codex `image_gen` on 18 November 2026, because a stock photo licenses the photographer's copyright but not the consent of the person in it, and Elena appears as a partner in ads for the app. `marketing/static/art/elena.webp` is the same image at 160 px. The original is `round2-candidate-1.png` in `~/agent-shots/paeonia/2026-11-18-elena-portrait/`, which expires after 14 days, so this file is the one to keep. Hjalmar's profile photo is `marketing/static/art/hjalmar.webp`, the developer's own photo.

The `question-*.jpg` photos are for the film's question recording (`scripts/app-store-content --question-film`). The script uploads all of them except `question-snow.jpg`, which Hjalmar picks in the recording, so it goes into the simulator's photo library with `xcrun simctl addmedia`.
