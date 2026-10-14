import Foundation

/// The "Surprise me" words for round 1. Each list is written for its language
/// and is not a translation of the other. Words are concrete and easy to picture,
/// so the first reveal is funny. Keep them lowercase and free of brand names,
/// slurs and crude second meanings, and have a native speaker read every change.
nonisolated enum MindMeldStarterWords {
    static let english: [String] = [
        "astronaut", "rocket", "spaceship", "comet", "planet", "moon", "galaxy", "telescope", "rainbow", "tornado",
        "volcano", "glacier", "waterfall", "desert", "island", "jungle", "canyon", "cave", "mountain", "ocean",
        "lighthouse", "submarine", "octopus", "dolphin", "shark", "whale", "turtle", "jellyfish", "penguin",
        "flamingo", "parrot", "owl", "giraffe", "elephant", "kangaroo", "panda", "monkey", "hedgehog", "squirrel",
        "raccoon", "bear", "llama", "camel", "zebra", "crocodile", "butterfly", "ladybug", "firefly", "dragon",
        "pirate", "treasure", "castle", "mermaid", "wizard", "unicorn", "robot", "ghost", "zombie", "ninja",
        "vampire", "princess", "superhero", "alien", "dinosaur", "pizza", "popcorn", "pancake", "waffle", "cupcake",
        "doughnut", "lollipop", "marshmallow", "pretzel", "burrito", "taco", "sushi", "spaghetti", "pineapple",
        "watermelon", "strawberry", "avocado", "pumpkin", "mushroom", "chocolate", "cheese", "honey", "cookie",
        "milkshake", "umbrella", "candle", "pillow", "blanket", "balloon", "kite", "guitar", "piano", "microphone",
        "camera", "suitcase", "postcard", "sunglasses", "pajamas", "slippers", "crown", "diamond", "compass",
        "backpack", "bicycle", "skateboard", "surfboard", "helicopter", "trampoline", "grandma", "grandpa",
        "firefighter", "cowboy", "detective", "clown", "magician", "wedding", "birthday", "picnic", "fireworks",
        "carnival", "circus", "museum", "aquarium", "playground", "skyscraper", "windmill", "barn", "treehouse",
        "campfire", "sauna", "igloo", "snowman", "snowflake", "sandcastle", "seashell", "sunflower", "tulip",
        "peony", "cactus", "puddle", "sunset", "wolf", "moose", "sled", "tractor", "bridge"
    ]

    static let norwegian: [String] = [
        "fjord", "fjell", "foss", "isbre", "nordlys", "midnattssol", "skog", "innsjø", "strand", "ørken", "jungel",
        "hule", "vulkan", "regnbue", "stjerne", "måne", "elg", "rein", "ulv", "bjørn", "isbjørn", "ørn", "ekorn",
        "hval", "krabbe", "laks", "pingvin", "hest", "katt", "hund", "kanin", "marihøne", "sommerfugl", "edderkopp",
        "ugle", "papegøye", "flamingo", "sjiraff", "elefant", "kenguru", "panda", "krokodille", "skilpadde",
        "blekksprut", "delfin", "pinnsvin", "pizza", "pannekake", "vaffel", "lefse", "lompe", "krumkake", "brunost",
        "geitost", "rømmegrøt", "fårikål", "lutefisk", "pinnekjøtt", "kjøttkake", "lapskaus", "fiskepinner",
        "leverpostei", "knekkebrød", "skolebrød", "sjokolade", "iskrem", "jordbær", "blåbær", "bringebær",
        "appelsin", "gresskar", "pepperkake", "taco", "matpakke", "paraply", "ski", "skøyter", "kjelke", "akebrett",
        "sykkel", "helikopter", "rakett", "romskip", "ballong", "drage", "gitar", "piano", "bamse", "dukke", "lue",
        "votter", "pyjamas", "solbriller", "diamant", "skatt", "bål", "lommelykt", "stearinlys", "dyne", "bestemor",
        "bestefar", "brannmann", "dronning", "prinsesse", "ridder", "pirat", "trollmann", "heks", "troll",
        "julenisse", "spøkelse", "vampyr", "romvesen", "astronaut", "superhelt", "klovn", "tryllekunstner",
        "bursdag", "bryllup", "juletre", "fyrverkeri", "sirkus", "piknik", "dugnad", "bunad", "hytte", "stavkirke",
        "slott", "fyrtårn", "bondegård", "lekeplass", "akvarium", "badstue", "snømann", "snøball", "iglo",
        "sandslott", "trampoline", "hybel", "løve", "solsikke", "kaktus", "ørret", "lørdagsgodt", "kanelsnurr",
        "hvalross", "vindmølle", "campingvogn", "hengekøye", "badeand", "dinosaur"
    ]

    static func words(for language: GameLanguage) -> [String] {
        switch language {
        case .en: english
        case .nb: norwegian
        }
    }

    /// A random word in the game language. `excluding` holds match keys
    /// (`MindMeldWord.matchKey`), so a word the person already typed is skipped
    /// however they spelled it. When every word is excluded it picks from all.
    static func random(
        for language: GameLanguage,
        excluding: Set<String>,
        using generator: inout some RandomNumberGenerator
    ) -> String {
        let all = words(for: language)
        let allowed = all.filter { !excluding.contains(MindMeldWord.matchKey($0)) }
        return (allowed.isEmpty ? all : allowed).randomElement(using: &generator) ?? all[0]
    }
}
