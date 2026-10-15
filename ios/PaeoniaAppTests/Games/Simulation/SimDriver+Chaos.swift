import Foundation
@testable import PaeoniaApp

/// What the world does to a phone: networks, the app's life, the relay, the clock.
extension SimDriver {
    private enum Chaos: CaseIterable {
        case offline, online, background, foreground, closeScreen, forceQuit, dropSocket, reconnect
        case reapGhosts, feedOutage, feedDelay, releaseHeld, smallTime, mediumTime, bigTime
        case changeLanguage, retrySync, weekPasses
    }

    func chaos(on phone: SimPhone) {
        let chaos = pickChaos(for: phone)
        switch chaos {
        case .offline, .online, .background, .foreground, .closeScreen, .forceQuit:
            changeAppState(chaos, phone)
        case .dropSocket, .reconnect, .reapGhosts, .feedOutage, .feedDelay, .releaseHeld:
            disturbConnection(chaos, phone)
        case .smallTime, .mediumTime, .bigTime, .weekPasses:
            letTimePass(chaos)
        case .changeLanguage, .retrySync:
            touchSettingsAndSync(chaos, phone)
        }
    }

    private func pickChaos(for phone: SimPhone) -> Chaos {
        random.weighted([
            (Chaos.offline, phone.network.isOnline ? 4 : 0),
            (.online, phone.network.isOnline ? 0 : 8),
            (.background, phone.isForeground ? 3 : 0),
            (.foreground, phone.isForeground ? 0 : 6),
            (.closeScreen, 2),
            (.forceQuit, 1.5),
            (.dropSocket, 2),
            (.reconnect, 5),
            (.reapGhosts, 2),
            (.feedOutage, 1.5),
            (.feedDelay, 1.5),
            (.releaseHeld, phone.network.heldCount > 0 ? 6 : 0),
            (.smallTime, 6),
            (.mediumTime, 3),
            (.bigTime, 0.6),
            (.changeLanguage, 0.8),
            (.retrySync, 3),
            (.weekPasses, hasWeekPassed ? 0 : 0.25),
        ])
    }

    private func changeAppState(_ chaos: Chaos, _ phone: SimPhone) {
        switch chaos {
        case .offline: phone.setOnline(false)
        case .online: phone.setOnline(true)
        case .background: phone.moveToBackground()
        case .foreground: phone.moveToForeground()
        case .closeScreen: phone.closeScreen()
        case .forceQuit: phone.forceQuit(closesSocket: random.chance(0.6))
        default: break
        }
    }

    private func disturbConnection(_ chaos: Chaos, _ phone: SimPhone) {
        switch chaos {
        case .dropSocket:
            log.add("\(phone.name) socket drop")
            phone.socket?.dropSilently()
        case .reconnect: phone.reconnectRelay()
        case .reapGhosts: relay.reapGhosts()
        case .feedOutage:
            phone.isFeedOutage.toggle()
            log.add("\(phone.name) feed outage \(phone.isFeedOutage)")
        case .feedDelay:
            phone.isFeedDelayed.toggle()
            log.add("\(phone.name) feed delayed \(phone.isFeedDelayed)")
        case .releaseHeld: phone.network.releaseHeld(count: random.int(1...max(1, phone.network.heldCount)))
        default: break
        }
    }

    private func letTimePass(_ chaos: Chaos) {
        switch chaos {
        case .smallTime: advanceTime(Double(random.int(1...6)))
        case .mediumTime: advanceTime(Double(random.int(20...45)))
        case .bigTime: advanceTime(Double(random.int(120...900)))
        case .weekPasses:
            // Only once a run: the app renews a gone upload at most once a day of real time.
            hasWeekPassed = true
            advanceTime(8 * 86_400)
            log.add("server swept \(server.sweepOrphanedUploads()) unused uploads")
        default: break
        }
    }

    private func touchSettingsAndSync(_ chaos: Chaos, _ phone: SimPhone) {
        switch chaos {
        case .changeLanguage:
            guard let games = phone.games, let settings = server.settings else { return }
            let language: GameLanguage = settings.language == .en ? .nb : .en
            log.add("\(phone.name) change language to \(language.rawValue)")
            let style: GamePlayStyle = random.chance(0.5) ? .against : .together
            Task { await games.saveSettings(playStyle: style, language: language) }
        case .retrySync:
            log.add("\(phone.name) retry timer")
            Task { await phone.sync() }
        default: break
        }
    }

    private func advanceTime(_ seconds: TimeInterval) {
        clock.advance(seconds)
        log.add("time +\(Int(seconds))s")
        relay.expireSessions()
        server.expirePresence()
        let beat = clock.now.timeIntervalSince(lastHeartbeat) >= 30
        if beat {
            lastHeartbeat = clock.now
        }
        for phone in phones {
            if beat {
                phone.heartbeat()
            }
            phone.tick()
        }
    }
}
