import Foundation
import Testing
@testable import PaeoniaApp

struct MediaDownloadCheckTests {
    @Test func aSignInPageIsNotMedia() {
        let page = Data("  <!doctype html><html></html>".utf8)

        #expect(MediaDownloadCheck.isWebPage(page, mimeType: nil))
        #expect(MediaDownloadCheck.isWebPage(Data([1, 2, 3]), mimeType: "text/html"))
        #expect(!MediaDownloadCheck.isWebPage(Data([0xFF, 0xD8, 0xFF]), mimeType: "image/jpeg"))
        #expect(!MediaDownloadCheck.isWebPage(Data([0, 0, 0, 0x20]), mimeType: "audio/mp4"))
    }

    @Test func aMissIsRememberedOnlyForTheRetryWindow() {
        var log = MediaMissLog(retryAfter: 60)
        let assetID = UUID()
        let start = Date(timeIntervalSince1970: 1_000)

        #expect(!log.isRecentMiss(assetID, now: start))
        log.record(assetID, now: start)
        #expect(log.isRecentMiss(assetID, now: start.addingTimeInterval(59)))
        #expect(!log.isRecentMiss(assetID, now: start.addingTimeInterval(60)))

        log.record(assetID, now: start)
        log.removeAll()
        #expect(!log.isRecentMiss(assetID, now: start))
    }

    @Test func onlyLastingFailuresAreRemembered() {
        #expect(MediaMissLog.isLasting(statusCode: 403))
        #expect(MediaMissLog.isLasting(statusCode: 404))
        #expect(!MediaMissLog.isLasting(statusCode: 408))
        #expect(!MediaMissLog.isLasting(statusCode: 429))
        #expect(!MediaMissLog.isLasting(statusCode: 500))
        #expect(!MediaMissLog.isLasting(URLError(.notConnectedToInternet)))
        #expect(MediaMissLog.isLasting(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))))
    }
}
