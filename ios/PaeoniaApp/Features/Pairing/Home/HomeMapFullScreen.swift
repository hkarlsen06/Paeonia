import MapKit
import SwiftUI

/// PROTOTYPE. The couple's map full screen, opened from Home. Both partners are small pins
/// that keep their size at every zoom, and merge into one pin when they would overlap.
struct HomeMapFullScreen: View {
    let current: LocationPoint
    let partner: LocationPoint
    let currentName: String
    let currentPhotoAssetID: UUID?
    let partnerName: String
    let partnerPhotoAssetID: UUID?

    @AppStorage("proto.home.avatarSize") private var avatarSize: Double = 72
    @AppStorage("proto.home.fakePartner") private var fakePartner: FakePartnerPlace = .real
    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition
    @State private var pins: Pins?

    init(
        current: LocationPoint,
        partner: LocationPoint,
        currentName: String,
        currentPhotoAssetID: UUID?,
        partnerName: String,
        partnerPhotoAssetID: UUID?
    ) {
        self.current = current
        self.partner = partner
        self.currentName = currentName
        self.currentPhotoAssetID = currentPhotoAssetID
        self.partnerName = partnerName
        self.partnerPhotoAssetID = partnerPhotoAssetID
        // Framed before the cover appears, so the zoom transition lands on both partners.
        let fake = FakePartnerPlace(rawValue: UserDefaults.standard.string(forKey: "proto.home.fakePartner") ?? "")
        _camera = State(initialValue: .region(CoupleMapFraming.region(
            current: current.coordinate,
            partner: fake?.coordinate ?? partner.coordinate,
            aspectRatio: 0.6
        )))
    }

    private static var pinSize: CGFloat { 40 }

    private var partnerCoordinate: CLLocationCoordinate2D {
        fakePartner.coordinate ?? partner.coordinate
    }

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(
                width: geo.size.width,
                height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            )
            ZStack {
                Map(position: $camera) {}
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .environment(\.colorScheme, .dark)
                    .grayscale(1)
                    .colorMultiply(.paeoniaAccentPrimary)
                    .ignoresSafeArea()
                    .onMapCameraChange(frequency: .continuous) { context in
                        guard MapScreenPoint.isUsable(context.rect) else { return }
                        pins = Pins(
                            own: MapScreenPoint.point(current.coordinate, in: context.rect, box: CGRect(origin: .zero, size: size)),
                            partner: MapScreenPoint.point(partnerCoordinate, in: context.rect, box: CGRect(origin: .zero, size: size))
                        )
                    }
                pinLayer
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) { controls }

            .onChange(of: fakePartner) { frame(size: size, insets: geo.safeAreaInsets) }

        }
        .background(Color.paeoniaBackgroundSecondary)
    }

    private func frame(size: CGSize, insets: EdgeInsets) {
        let height = size.height - insets.top - insets.bottom - 120
        guard size.width > 0, height > 0 else { return }
        camera = .region(CoupleMapFraming.region(
            current: current.coordinate,
            partner: partnerCoordinate,
            aspectRatio: size.width / height
        ))
    }

    @ViewBuilder
    private var pinLayer: some View {
        if let pins {
            let distance = hypot(pins.partner.x - pins.own.x, pins.partner.y - pins.own.y)
            if distance < Self.pinSize + PaeoniaSpacing.space8 {
                // One pin for both, with the two faces overlapping.
                HStack(spacing: -Self.pinSize * 0.35) {
                    pin(currentName, currentPhotoAssetID, tint: .paeoniaPartnerOne)
                    pin(partnerName, partnerPhotoAssetID, tint: .paeoniaPartnerTwo)
                }
                .position(x: (pins.own.x + pins.partner.x) / 2, y: (pins.own.y + pins.partner.y) / 2)
            } else {
                pin(currentName, currentPhotoAssetID, tint: .paeoniaPartnerOne)
                    .position(pins.own)
                pin(partnerName, partnerPhotoAssetID, tint: .paeoniaPartnerTwo)
                    .position(pins.partner)
            }
        }
    }

    private func pin(_ name: String, _ assetID: UUID?, tint: Color) -> some View {
        PaeoniaProfilePhotoAvatar(mediaAssetID: assetID, name: name, tint: tint, size: Self.pinSize)
            .padding(3)
            .background(Circle().fill(Color.paeoniaTextPrimary))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
    }

    private var controls: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel(Text(verbatim: "Close"))

            Menu {
                Picker(selection: $avatarSize) {
                    Text(verbatim: "64").tag(64.0)
                    Text(verbatim: "72 (today's size)").tag(72.0)
                    Text(verbatim: "84").tag(84.0)
                } label: {
                    Text(verbatim: "Home avatar size")
                }
                Picker(selection: $fakePartner) {
                    ForEach(FakePartnerPlace.allCases, id: \.self) { place in
                        Text(verbatim: place.label).tag(place)
                    }
                } label: {
                    Text(verbatim: "Partner location")
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .accessibilityLabel(Text(verbatim: "Prototype settings"))
        }
        .padding(.trailing, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space8)
    }
}

private struct Pins: Equatable {
    let own: CGPoint
    let partner: CGPoint
}
