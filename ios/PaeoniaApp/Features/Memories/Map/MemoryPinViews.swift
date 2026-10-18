import MapKit
import SwiftUI
import UIKit

/// Pin geometry and colors. Memories are rounded tiles with a petal mist ring, so they
/// never read as a partner, who is a round avatar on the couple map.
enum MemoryPinStyle {
    static let tileSize: CGFloat = 48
    static let cornerRadius: CGFloat = 12
    static let ringWidth: CGFloat = 2.5
    static let tailSize = CGSize(width: 12, height: 8)
    static let selectedScale: CGFloat = 1.18
    /// Decoded size of a pin photo: a 48 pt tile at 3x.
    static let photoPixelSize = 160
    static let raisedZPriority = MKAnnotationViewZPriority(rawValue: MKAnnotationViewZPriority.max.rawValue - 1)

    static let ring = UIColor(Color.paeoniaMemory)
    static let selectedRing = UIColor.paeoniaAccentPrimary
    static let emptyTile = UIColor(Color.paeoniaSurfacePrimary)
    static let badge = UIColor.paeoniaAccentSecondary
    static let badgeText = UIColor(Color.paeoniaTextPrimary)
    static let badgeRing = UIColor(Color.paeoniaBackgroundSecondary)
}

/// One rounded photo tile: the memory's first photo, or a heart when it has none.
final class MemoryPinTileView: UIView {
    private let imageView = UIImageView()
    private let heartView = UIImageView(image: UIImage(systemName: "heart.fill"))
    private var assetID: UUID?
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = MemoryPinStyle.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = MemoryPinStyle.ringWidth
        layer.borderColor = MemoryPinStyle.ring.cgColor
        layer.masksToBounds = true
        backgroundColor = MemoryPinStyle.emptyTile

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        heartView.tintColor = MemoryPinStyle.ring
        heartView.contentMode = .scaleAspectFit
        heartView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        addSubview(imageView)
        addSubview(heartView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        heartView.frame = bounds.insetBy(dx: 12, dy: 12)
    }

    var ringColor: UIColor = MemoryPinStyle.ring {
        didSet { layer.borderColor = ringColor.cgColor }
    }

    /// Shows the photo, from the decoded-image cache right away when it is there.
    func show(photoAssetID: UUID?) {
        guard photoAssetID != assetID || (photoAssetID != nil && imageView.image == nil) else { return }
        assetID = photoAssetID
        loadTask?.cancel()
        heartView.isHidden = photoAssetID != nil
        guard let photoAssetID else {
            imageView.image = nil
            return
        }
        let size = MemoryPinStyle.photoPixelSize
        if let cached = MemoryImageDecoding.cachedImage(for: photoAssetID, maxPixelSize: size) {
            imageView.image = cached
            return
        }
        imageView.image = nil
        loadTask = Task { [weak self] in
            guard let data = await MemoryMediaImageProviderFactory.shared?.imageData(for: photoAssetID),
                  let image = await MemoryImageDecoding.downsample(data, maxPixelSize: size)
            else { return }
            MemoryImageDecoding.store(image, for: photoAssetID, maxPixelSize: size)
            guard !Task.isCancelled, let self, self.assetID == photoAssetID else { return }
            UIView.transition(with: self.imageView, duration: 0.2, options: .transitionCrossDissolve) {
                self.imageView.image = image
            }
        }
    }
}

/// The small pointer under a tile. Its tip marks the exact spot.
final class MemoryPinTailView: UIView {
    private let shape = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        // `didSet` doesn't run in init, so set the fill here too.
        shape.fillColor = color.cgColor
        layer.addSublayer(shape)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var color: UIColor = MemoryPinStyle.ring {
        didSet { shape.fillColor = color.cgColor }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: bounds.width, y: 0))
        path.addLine(to: CGPoint(x: bounds.midX, y: bounds.height))
        path.close()
        shape.path = path.cgPath
        shape.frame = bounds
    }
}

/// A single memory's pin.
final class MemoryPinAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "memory-pin"
    static let clusteringIdentifier = "memory"

    private let body = UIView()
    private let tile = MemoryPinTileView()
    private let tail = MemoryPinTailView()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let tileSize = MemoryPinStyle.tileSize
        let tailSize = MemoryPinStyle.tailSize
        frame = CGRect(x: 0, y: 0, width: tileSize, height: tileSize + tailSize.height - 1)
        // The tail's tip sits on the coordinate.
        centerOffset = CGPoint(x: 0, y: -frame.height / 2)
        clusteringIdentifier = Self.clusteringIdentifier
        collisionMode = .rectangle
        canShowCallout = false
        isAccessibilityElement = true
        accessibilityTraits = .button

        body.frame = bounds
        body.layer.shadowColor = UIColor.black.cgColor
        body.layer.shadowOpacity = 0.4
        body.layer.shadowRadius = 4
        body.layer.shadowOffset = CGSize(width: 0, height: 3)
        tile.frame = CGRect(x: 0, y: 0, width: tileSize, height: tileSize)
        tail.frame = CGRect(
            x: (tileSize - tailSize.width) / 2,
            y: tileSize - 1,
            width: tailSize.width,
            height: tailSize.height
        )
        body.addSubview(tail)
        body.addSubview(tile)
        addSubview(body)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let entry = (annotation as? MemoryMapAnnotation)?.entry else { return }
        tile.show(photoAssetID: entry.photoAssetID)
        accessibilityLabel = Self.accessibilityLabel(for: entry)
        applySelection(animated: false)
    }

    /// Whether this memory's card shows. Drawn by the pin itself rather than through
    /// MapKit's selection, which would pull a clustered memory out of its cluster.
    var showsSelection = false

    func setShowsSelection(_ shows: Bool, animated: Bool) {
        guard shows != showsSelection else { return }
        showsSelection = shows
        applySelection(animated: animated)
    }

    /// Grows from the tail's tip, so the pin keeps pointing at its spot.
    private func applySelection(animated: Bool) {
        let isSelected = showsSelection
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        let scale = isSelected ? MemoryPinStyle.selectedScale : 1
        let lift = bounds.height * (scale - 1) / 2
        let changes = {
            self.body.transform = CGAffineTransform(translationX: 0, y: -lift).scaledBy(x: scale, y: scale)
            self.tile.ringColor = isSelected ? MemoryPinStyle.selectedRing : MemoryPinStyle.ring
            self.tail.color = isSelected ? MemoryPinStyle.selectedRing : MemoryPinStyle.ring
        }
        // Raised above other pins, but below `.max`: MapKit treats a pin at `.max` like a
        // selected one and takes it out of its cluster.
        zPriority = isSelected ? MemoryPinStyle.raisedZPriority : .defaultUnselected
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            changes()
            return
        }
        UIView.animate(springDuration: 0.3, bounce: 0.25, animations: changes)
    }

    static func accessibilityLabel(for entry: MemoryMapEntry) -> String {
        let date = MemoryTimeline.parseLocalDate(entry.memoryDate)
            .map { $0.formatted(MemoryDateStyle.long) }
        return [entry.title, entry.place.nameAndCity, date].compactMap(\.self).joined(separator: ", ")
    }
}

/// Several memories close together: the newest photo on top of two fanned tiles, and
/// a pink count.
final class MemoryClusterAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "memory-cluster"

    private let body = UIView()
    private let backTile = MemoryPinTileView()
    private let middleTile = MemoryPinTileView()
    private let frontTile = MemoryPinTileView()
    private let tail = MemoryPinTailView()
    private let badge = UILabel()
    /// The cluster's memories, newest first.
    private var entries: [MemoryMapEntry] = []
    /// The memory whose card shows, set before MapKit displays the view.
    var selectedMemoryID: UUID?

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let tileSize = MemoryPinStyle.tileSize
        let tailSize = MemoryPinStyle.tailSize
        // Room around the tile for the fanned tiles and the badge.
        let inset: CGFloat = 12
        frame = CGRect(x: 0, y: 0, width: tileSize + inset * 2, height: tileSize + tailSize.height - 1 + inset * 2)
        centerOffset = CGPoint(x: 0, y: -(frame.height / 2 - inset))
        collisionMode = .rectangle
        canShowCallout = false
        displayPriority = .required
        isAccessibilityElement = true
        accessibilityTraits = .button

        body.frame = bounds
        body.layer.shadowColor = UIColor.black.cgColor
        body.layer.shadowOpacity = 0.4
        body.layer.shadowRadius = 4
        body.layer.shadowOffset = CGSize(width: 0, height: 3)

        let tileFrame = CGRect(x: inset, y: inset, width: tileSize, height: tileSize)
        // Fanned wide enough to read as a stack of prints at a glance.
        for (view, angle, shift) in [(backTile, -10.0, -4.0), (middleTile, 8.0, 4.0)] {
            view.frame = tileFrame
            view.transform = CGAffineTransform(translationX: shift, y: 3).rotated(by: angle * .pi / 180)
            body.addSubview(view)
        }
        tail.frame = CGRect(
            x: inset + (tileSize - tailSize.width) / 2,
            y: inset + tileSize - 1,
            width: tailSize.width,
            height: tailSize.height
        )
        body.addSubview(tail)
        frontTile.frame = tileFrame
        body.addSubview(frontTile)

        setUpBadge()
        body.addSubview(badge)
        addSubview(body)
    }

    /// Lights up the cluster when the memory whose card shows is inside it, the same
    /// way a single selected pin grows and turns pink, and puts that memory's photo on
    /// top of the stack. Otherwise the newest memory is on top.
    func showSelectedMemory(_ selectedID: UUID?, animated: Bool) {
        selectedMemoryID = selectedID
        let holds = entries.contains { $0.id == selectedID }
        let ordered = holds
            ? entries.filter { $0.id == selectedID } + entries.filter { $0.id != selectedID }
            : entries
        frontTile.show(photoAssetID: ordered.first?.photoAssetID)
        middleTile.show(photoAssetID: ordered.dropFirst().first?.photoAssetID)
        backTile.show(photoAssetID: ordered.dropFirst(2).first?.photoAssetID)

        let scale = holds ? MemoryPinStyle.selectedScale : 1
        let lift = bounds.height * (scale - 1) / 2
        let changes = {
            self.body.transform = CGAffineTransform(translationX: 0, y: -lift).scaledBy(x: scale, y: scale)
            self.frontTile.ringColor = holds ? MemoryPinStyle.selectedRing : MemoryPinStyle.ring
            self.tail.color = holds ? MemoryPinStyle.selectedRing : MemoryPinStyle.ring
        }
        zPriority = holds ? .max : .defaultUnselected
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            changes()
            return
        }
        UIView.animate(springDuration: 0.3, bounce: 0.25, animations: changes)
    }

    private func setUpBadge() {
        badge.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        badge.textColor = MemoryPinStyle.badgeText
        badge.backgroundColor = MemoryPinStyle.badge
        badge.textAlignment = .center
        badge.layer.cornerRadius = 11
        badge.layer.cornerCurve = .continuous
        badge.layer.borderWidth = 2
        badge.layer.borderColor = MemoryPinStyle.badgeRing.cgColor
        badge.layer.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        entries = cluster.memoryEntries
        showSelectedMemory(selectedMemoryID, animated: false)
        badge.text = MemoryClusterBadge.label(count: entries.count)
        let width = max(22, badge.intrinsicContentSize.width + 12)
        let tileRight = frontTile.frame.maxX
        badge.frame = CGRect(x: tileRight - width + 10, y: frontTile.frame.minY - 9, width: width, height: 22)

        accessibilityLabel = entries.count == 1
            ? String(localized: .memoriesMapMemoryCountOne)
            : String(localized: .memoriesMapMemoryCount(entries.count.formatted()))
        accessibilityHint = String(localized: .memoriesMapClusterHint)
    }
}
