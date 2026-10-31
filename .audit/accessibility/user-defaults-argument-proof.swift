#!/usr/bin/env swift
import Foundation

// This proves Foundation preference priority, not UIKit's private override or audit implementation.
// Run with: swift <file> -UIPreferredContentSizeCategoryName UICTContentSizeCategoryL
let key = "UIPreferredContentSizeCategoryName"
let suiteName = "PaeoniaAuditArgumentProof-\(UUID().uuidString)"
guard let defaults = UserDefaults(suiteName: suiteName) else { exit(1) }
defer { defaults.removePersistentDomain(forName: suiteName) }
let argument = defaults.volatileDomain(forName: UserDefaults.argumentDomain)[key] as? String
guard argument == "UICTContentSizeCategoryL" else { exit(2) }
defaults.set("UICTContentSizeCategoryAccessibilityXXXL", forKey: key)
guard defaults.string(forKey: key) == argument else { exit(3) }
let result = "Argument L still overrides a stored AX5 value in an isolated defaults suite.\n"
FileHandle.standardOutput.write(Data(result.utf8))
