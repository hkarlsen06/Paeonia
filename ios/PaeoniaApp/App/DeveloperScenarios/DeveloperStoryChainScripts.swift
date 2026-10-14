#if DEBUG
  import Foundation

  /// The story text and suggestions of the Story Chain scenarios. The text is
  /// sample content, not catalog copy, and it does not depend on who wrote a
  /// line, so one script serves every scenario.
  nonisolated extension DeveloperStoryChainFixture {
    // MARK: Story 4, "The Lighthouse Key"

    static let opening = RemoteStoryOpening(
      openingID: "key_under_bench",
      text: "The key had been taped under the bench for years."
    )

    /// Lines 1 to 12. Four of them dare the next line: lighthouse, umbrella, ladder, kettle.
    static let lighthouse: [Beat] = [
      Beat(
        """
        Ines only noticed it on Monday, when it started to hum like an old refrigerator \
        and she felt it through the wood.
        """
      ),
      Beat("She peeled it off, and a tag fell out of the tape that said, in tiny letters, Not before Tuesday."),
      Beat(
        "Ines carried it to the only person in town who understood locks, a retired baker named Otto.",
        dare: "lighthouse"
      ),
      Beat(
        """
        Otto squinted at the key and said it was far too big for any door in town, \
        but it might fit the lighthouse on the cliff.
        """
      ),
      Beat(
        """
        Ines reminded him that the lighthouse had been locked since before she was born, \
        so he handed her a pancake for the walk and wished her luck.
        """
      ),
      Beat("Halfway up the cliff path it began to rain, and the pancake was no help at all.", dare: "umbrella"),
      Beat(
        """
        Luckily she had her umbrella, and under it the key hummed so loudly \
        that a passing seagull stopped to listen.
        """
      ),
      Beat(
        """
        At the top, a small green door in the lighthouse wall swung open by itself, \
        and a voice inside called, Wipe your feet, you're late.
        """,
        dare: "ladder"
      ),
      Beat(
        """
        Ines wiped her feet, climbed the dark stairs, \
        and found a ladder that led up to a round room full of tangled lamps.
        """
      ),
      Beat(
        """
        In the middle sat a tiny old keeper named Greta, who said she had been taping keys \
        under benches for years, hoping that someone curious would find one.
        """,
        dare: "kettle"
      ),
      Beat(
        """
        Nobody ever had, she said, until today, \
        so she put the kettle on and handed Ines a cookie the size of a plate.
        """
      ),
      Beat(
        """
        They talked past midnight, and Greta showed her how the great lamp worked, \
        which turned out to be mostly a matter of being polite to it.
        """
      ),
    ]

    /// Line 13 when the story ends here.
    static let lighthouseEnding = Beat(
      """
      At the stroke of Tuesday the beam switched on, the whole bay glowed gold, \
      and in Ines's pocket the key stopped humming and fell asleep.
      """
    )

    /// Lines 13 to 19 when the story goes on. Line 19 dares line 20 to use "tuesday".
    static let lighthouseDetour: [Beat] = [
      Beat(
        """
        Greta checked a pocket watch the size of a saucer and gasped, \
        because Tuesday was only four minutes away.
        """
      ),
      Beat(
        """
        They hurried up the last steps, Ines tripped over a bucket, \
        and the bucket tripped over a cat nobody had mentioned.
        """
      ),
      Beat(
        """
        The cat, whose name was Commander Biscuit, was not at all sorry \
        and sat on the great lamp as if he had paid for it.
        """
      ),
      Beat(
        """
        Greta whispered that the lamp only started for someone it respected, \
        and Commander Biscuit respected nobody.
        """
      ),
      Beat(
        """
        So Ines did the only thing she could think of and offered him the rest of Otto's pancake, \
        which had survived the rain next to the key.
        """
      ),
      Beat("Commander Biscuit sniffed it, thought about it for a long, long moment, and finally stepped aside."),
      Beat(
        "The clock began to chime twelve, and the lamp gave a low, sleepy hum that sounded a lot like the key.",
        dare: "tuesday"
      ),
    ]

    /// The line Robin types in the live scenario: line 8.
    static var partnerLiveLine: Beat {
      lighthouse[7]
    }

    // MARK: Suggestions

    static let openings = [
      RemoteStoryOpening(
        openingID: "cat_mayor",
        text: "The town cat was elected mayor again, and this time it had a plan."
      ),
      RemoteStoryOpening(
        openingID: "fog_jars",
        text: "At the night market, a woman was selling jars of fog, and the jar marked Tuesday was almost sold out."
      ),
      RemoteStoryOpening(
        openingID: "cloud_ladder",
        text: "A tall ladder leaned against the clouds one morning, with a note on the bottom step that said back soon."
      ),
    ]

    static let words = [
      RemoteStoryDareWord(wordID: "lantern", word: "lantern"),
      RemoteStoryDareWord(wordID: "compass", word: "compass"),
      RemoteStoryDareWord(wordID: "hammock", word: "hammock"),
    ]

    // MARK: Older stories

    static let goatBeats: [Beat] = [
      Beat("Nobody ever asked where the goat was going, because he always looked like he had a meeting."),
      Beat("One Monday Mira finally asked, and the goat calmly said he was late for his own surprise party."),
      Beat(
        "That was news to everyone, especially to the nervous librarian who had been planning it for weeks.",
        dare: "balloon"
      ),
      Beat(
        """
        Folke had forty balloons in the back room and no goat-sized hat, \
        so the whole library went into a panic.
        """
      ),
      Beat(
        """
        Mira solved it by borrowing a lampshade, \
        which the goat said suited him better than any hat he had ever owned.
        """
      ),
      Beat("The party was a great success until the goat ate the cake, the candles, and a little of the tablecloth."),
      Beat("Folke forgave him, because the goat gave a speech about how nice it is to be expected somewhere."),
      Beat(
        """
        The next morning he was back at the bus stop at seven, wearing the lampshade, \
        and this time two people waited with him.
        """
      ),
    ]

    static let bakeryBeats: [Beat] = [
      Beat(
        """
        Tilda decided to find out, so she sat on the bench across the street \
        with a thermos and a very serious expression.
        """
      ),
      Beat(
        """
        At two minutes to midnight a light came on, \
        and at midnight exactly the door opened by itself, which she thought was rude.
        """
      ),
      Beat(
        "Inside, a tray of rolls hovered three inches above the counter, and every roll wore a tiny paper hat.",
        dare: "apron"
      ),
      Beat(
        """
        A baker came out of the back in a tall apron, saw Tilda, \
        and said she was the first customer in eleven years.
        """
      ),
      Beat("Tilda bought a loaf, and the baker asked her not to tell anyone, because the rolls got shy in crowds."),
      Beat("She promised, then spent the whole walk home trying not to tell anybody, which is harder than it sounds."),
      Beat(
        """
        By Friday she had told exactly one person, who told exactly one person, \
        and soon half the street sat on the bench at midnight.
        """
      ),
      Beat(
        """
        At two minutes to midnight the light came on, the door opened, \
        and the baker waved at all of them as if he had expected a crowd all along.
        """
      ),
    ]

    static let scarfBeats: [Beat] = [
      Beat("The mayor called it vandalism, but the lamp posts looked so cozy that nobody wanted to say it out loud."),
      Beat(
        """
        Jonas stayed up the next night behind a bush, \
        wrapped in three blankets and holding one very old thermos of cocoa.
        """
      ),
      Beat(
        "At two in the morning a small figure appeared with a basket of wool, and Jonas nearly dropped the cocoa.",
        dare: "needle"
      ),
      Beat("It was his grandmother, holding two enormous needles and looking like a burglar who had given up halfway."),
      Beat(
        """
        Grandma explained that the lamp posts looked cold in November, \
        and that it was nobody's business but hers.
        """
      ),
      Beat("Jonas joined her, and by sunrise they had run out of lamp posts and started on the benches."),
      Beat("The mayor found out, frowned for a very long time, and then quietly asked if she had a hat in his size."),
      Beat(
        """
        The scarves stayed all winter, \
        and in spring the whole town agreed to leave them up until they fell apart.
        """
      ),
    ]
  }
#endif
