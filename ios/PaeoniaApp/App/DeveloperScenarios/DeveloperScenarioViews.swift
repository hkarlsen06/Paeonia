#if DEBUG
  import SwiftUI

  struct DeveloperScenarioMenu: View {
    let runProductionApp: () -> Void
    // Scenarios open full screen, not pushed. Several screens own a NavigationStack, and
    // one nested inside the menu's stack can cancel the push (the Games tab binds a path).
    @State private var openScenario: DeveloperScenario?
    @State private var collapsedCategories: Set<DeveloperScenario.Category> = []
    @State private var searchText = ""

    var body: some View {
      NavigationStack {
        List {
          ForEach(visibleCategories) { category in
            let scenarios = scenarios(in: category)
            Section("\(category.rawValue) (\(scenarios.count))", isExpanded: isExpanded(category)) {
              ForEach(scenarios, content: scenarioRow)
            }
          }

          if searchText.isEmpty {
            Section {
              Button("Run production app") {
                runProductionApp()
              }
              .accessibilityIdentifier("developer.scenario.production")
            }
          }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle("Developer Scenarios")
        .searchable(text: $searchText, prompt: "Title, detail or id")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            let allCollapsed = collapsedCategories.count == DeveloperScenario.Category.allCases.count
            Button(allCollapsed ? "Expand all" : "Collapse all") {
              collapsedCategories = allCollapsed ? [] : Set(DeveloperScenario.Category.allCases)
            }
            .disabled(!searchText.isEmpty)
          }
        }
      }
      .fullScreenCover(item: $openScenario) { scenario in
        DeveloperScenarioHost(scenario: scenario) {
          openScenario = nil
        }
      }
      .preferredColorScheme(.dark)
      .accessibilityIdentifier("developer.scenario.menu")
    }

    private func scenarioRow(_ scenario: DeveloperScenario) -> some View {
      Button {
        openScenario = scenario
      } label: {
        HStack {
          scenarioLabel(scenario)
          Spacer(minLength: 0)
          Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.paeoniaTextTertiary)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("developer.scenario.\(scenario.rawValue)")
    }

    private func scenarioLabel(_ scenario: DeveloperScenario) -> some View {
      VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
        Text(scenario.title)
          .foregroundStyle(.paeoniaTextPrimary)
        Text(scenario.detail)
          .font(PaeoniaTypography.caption)
          .foregroundStyle(.paeoniaTextSecondary)
        Text(scenario.rawValue)
          .font(.caption2.monospaced())
          .foregroundStyle(.paeoniaTextTertiary)
      }
      .padding(.vertical, PaeoniaSpacing.space4)
    }

    private var visibleCategories: [DeveloperScenario.Category] {
      DeveloperScenario.Category.allCases.filter { !scenarios(in: $0).isEmpty }
    }

    private func scenarios(in category: DeveloperScenario.Category) -> [DeveloperScenario] {
      DeveloperScenario.allCases.filter { scenario in
        scenario.category == category
          && (searchText.isEmpty
            || [scenario.title, scenario.detail, scenario.rawValue].contains {
              $0.localizedStandardContains(searchText)
            })
      }
    }

    // Search results ignore collapsed state so a match is never hidden.
    private func isExpanded(_ category: DeveloperScenario.Category) -> Binding<Bool> {
      Binding {
        !searchText.isEmpty || !collapsedCategories.contains(category)
      } set: { expanded in
        if expanded {
          collapsedCategories.remove(category)
        } else {
          collapsedCategories.insert(category)
        }
      }
    }
  }

  struct DeveloperScenarioHost: View {
    let scenario: DeveloperScenario
    let returnToMenu: () -> Void
    @State private var bannerCenter = PaeoniaBannerCenter()
    @State private var reloadID = UUID()

    var body: some View {
      scenarioContent
        .id(reloadID)
        .environment(bannerCenter)
        .preferredColorScheme(.dark)
        // No host-level accessibilityIdentifier here: a container identifier
        // cascades onto every descendant element, replacing the production
        // identifiers (auth.signIn.apple, legal.privacy, …) UI tests query.
        .overlay(alignment: .topTrailing) {
          // `-paeonia-scenario-hide-controls YES` hides these buttons for screenshots
          // of the toolbar they cover.
          if !UserDefaults.standard.bool(forKey: "paeonia-scenario-hide-controls") {
            scenarioControls
          }
        }
    }

    private var scenarioControls: some View {
      HStack(spacing: PaeoniaSpacing.space8) {
        Button {
          reloadID = UUID()
        } label: {
          Image(systemName: "arrow.counterclockwise")
            .frame(width: 44, height: 44)
            .background(.paeoniaSurfacePrimary.opacity(0.92), in: Circle())
        }
        .accessibilityLabel("Reset scenario")
        .accessibilityIdentifier("developer.scenario.reset")

        Button(action: returnToMenu) {
          Image(systemName: "wrench.and.screwdriver.fill")
            .frame(width: 44, height: 44)
            .background(.paeoniaSurfacePrimary.opacity(0.92), in: Circle())
        }
        .accessibilityLabel("Return to developer scenarios")
        .accessibilityIdentifier("developer.scenario.return")
      }
      .foregroundStyle(.paeoniaTextPrimary)
      .padding(.top, PaeoniaSpacing.space8)
      .padding(.trailing, PaeoniaSpacing.space8)
    }

    private var scenarioContent: some View {
      scenario.makeView()
    }
  }

  /// Opens every scenario in turn, then shows a done marker. One UI test launch
  /// checks that no scenario crashes on open, without tapping through the menu.
  struct DeveloperScenarioTour: View {
    @State private var index = 0

    var body: some View {
      if DeveloperScenario.allCases.indices.contains(index) {
        DeveloperScenarioHost(scenario: DeveloperScenario.allCases[index]) {}
          .id(index)
          .task(id: index) {
            try? await Task.sleep(for: .milliseconds(50))
            index += 1
          }
      } else {
        Text("Opened \(index) scenarios")
          .accessibilityIdentifier("developer.scenario.tour.done")
      }
    }
  }
#endif
